import CryptoKit
import Foundation

/// Kimi Code keeps each session under `~/.kimi-code/sessions/<workdir key>/
/// session_<uuid>/`, its main agent's record in `agents/main/wire.jsonl`:
/// one JSON record per line with a `type` and an epoch-millisecond `time`.
/// `session_index.jsonl` says which folder each session ran in.
public struct KimiHarness: ContextHarnessReader {
    public let harness = HarnessID.kimi
    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public static func defaultHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["KIMI_CODE_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".kimi-code")
    }

    /// Kimi Code's own folder name for a working directory
    /// (`workdir-slug.ts`): the last path part as a slug, then the first 12
    /// hex digits of the path's SHA-256.
    public static func workdirKey(for path: String) -> String {
        var normalized = path.replacingOccurrences(of: "\\", with: "/")
        while normalized.hasSuffix("/") { normalized.removeLast() }
        let base = normalized.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        var slug = ""
        var inRejectedRun = false
        for scalar in base.lowercased().unicodeScalars {
            let allowed = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || ".-_".unicodeScalars.contains(scalar)
            if allowed {
                slug.unicodeScalars.append(scalar)
                inRejectedRun = false
            } else if !inRejectedRun {
                slug.append("-")
                inRejectedRun = true
            }
        }
        func trimDashes(_ text: String) -> String {
            String(text.drop { $0 == "-" }.reversed().drop { $0 == "-" }.reversed())
        }
        slug = trimDashes(String(trimDashes(slug).prefix(40)))
        if slug.isEmpty || slug == "." || slug == ".." { slug = "workspace" }
        let digest = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return "wd_\(slug)_\(digest.prefix(12))"
    }

    public func recentTranscripts(for project: URL, limit: Int, fileManager: FileManager) -> [ContextTranscriptFile] {
        let cwd = project.standardizedFileURL.path
        let index = indexedSessions(for: cwd, fileManager: fileManager)
        var sessionDirs = index.dirs
        if !index.indexed {
            let folder = home.appendingPathComponent("sessions").appendingPathComponent(Self.workdirKey(for: cwd))
            sessionDirs = ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("session_") }
        }
        let files = sessionDirs.compactMap { dir -> ContextTranscriptFile? in
            let wire = dir.appendingPathComponent("agents/main/wire.jsonl")
            guard let modified = contextModified(wire) else { return nil }
            return ContextTranscriptFile(path: wire, modified: modified)
        }
        return contextRecent(files, limit: limit)
    }

    /// The index stores each session's absolute folder; when that folder is
    /// gone (the data moved), the same session is looked for under this home.
    /// `indexed` is false when the index knows nothing of this folder, even a
    /// deleted session, and only then is the folder Kimi would use listed.
    private func indexedSessions(for cwd: String, fileManager: FileManager) -> (dirs: [URL], indexed: Bool) {
        guard let text = try? String(contentsOf: home.appendingPathComponent("session_index.jsonl"), encoding: .utf8)
        else { return ([], false) }
        var dirs: [String: URL] = [:]
        var deleted = Set<String>()
        text.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = entry["sessionId"] as? String
            else { return }
            if entry["deleted"] as? Bool == true {
                deleted.insert(id)
                return
            }
            guard entry["workDir"] as? String == cwd, let sessionDir = entry["sessionDir"] as? String else { return }
            deleted.remove(id)
            let recorded = URL(fileURLWithPath: sessionDir)
            let local = home.appendingPathComponent("sessions")
                .appendingPathComponent(recorded.deletingLastPathComponent().lastPathComponent)
                .appendingPathComponent(id)
            dirs[id] = fileManager.fileExists(atPath: recorded.path) ? recorded : local
        }
        return (dirs.filter { !deleted.contains($0.key) }.map(\.value), !dirs.isEmpty)
    }

    public func pass(for transcript: ContextTranscriptFile) -> ContextHarnessPass {
        Self.extract(events: ContextJSONLReader.events(at: transcript.path))
    }

    public static func extract(events: [[String: Any]]) -> ContextHarnessPass {
        var pass = ContextHarnessPass()
        var newest = ""
        var todos: [[String: Any]]?
        var subagents: [String: (label: String, started: String)] = [:]
        var subagentOrder: [String] = []

        for record in events {
            guard let type = record["type"] as? String else { continue }
            let ts = (record["time"] as? Double).map { contextISO(milliseconds: $0) } ?? ""
            if ts > newest { newest = ts }

            switch type {
            case "turn.prompt":
                guard (record["origin"] as? [String: Any])?["kind"] as? String == "user" else { continue }
                for part in record["input"] as? [[String: Any]] ?? [] {
                    if let text = part["text"] as? String { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
                }
            case "context.append_loop_event":
                guard let event = record["event"] as? [String: Any] else { continue }
                switch event["type"] as? String {
                case "content.part":
                    let part = event["part"] as? [String: Any]
                    if part?["type"] as? String == "text", let text = part?["text"] as? String {
                        pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                    }
                case "tool.call":
                    if let text = contextJSONText(event["args"]) { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
                case "tool.result":
                    let result = event["result"] as? [String: Any]
                    if let text = kimiOutputText(result?["output"]) {
                        pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                    }
                default:
                    continue
                }
            case "tools.update_store":
                if record["key"] as? String == "todo" { todos = record["value"] as? [[String: Any]] ?? [] }
            case "subagent.spawned", "subagent.started":
                guard let id = record["subagentId"] as? String else { continue }
                if subagents[id] == nil {
                    let label = contextLabel((record["description"] as? String) ?? (record["subagentName"] as? String))
                    subagents[id] = (label.isEmpty ? id : label, ts)
                    subagentOrder.append(id)
                }
            case "subagent.completed", "subagent.failed", "subagent.cancelled":
                if let id = record["subagentId"] as? String { subagents[id] = nil }
            default:
                continue
            }
        }

        pass.todoItems = (todos ?? []).map {
            ContextEngineResult.PlanItem(text: $0["title"] as? String ?? "", state: kimiTodoState($0["status"] as? String))
        }
        pass.agents = subagentOrder.compactMap { id in
            guard let agent = subagents[id], !contextIsStale(agent.started, newest: newest) else { return nil }
            return ContextEngineResult.Agent(label: agent.label, status: "running")
        }
        pass.newestTimestamp = newest
        return pass
    }
}

private func kimiOutputText(_ output: Any?) -> String? {
    if let text = output as? String { return text }
    guard let parts = output as? [[String: Any]] else { return nil }
    let texts = parts.compactMap { $0["text"] as? String }
    return texts.isEmpty ? nil : texts.joined(separator: "\n")
}

private func kimiTodoState(_ raw: String?) -> String {
    switch raw {
    case "done": return "done"
    case "in_progress": return "active"
    default: return "pending"
    }
}
