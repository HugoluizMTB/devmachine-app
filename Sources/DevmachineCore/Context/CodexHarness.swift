import Foundation

/// Codex CLI transcript discovery and extraction:
/// `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, one event per line with a
/// `type` (`session_meta`, `response_item`, `event_msg`, …) and `payload`.
///
/// Codex records no per-session working directory in its file layout (unlike
/// Claude's slug-per-project folder), so a transcript is matched to a
/// project by reading its own `session_meta.payload.cwd`.
public enum CodexHarness {
    public static let sessionsDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex/sessions")

    /// The session's first line (`session_meta`) can run past 16 KB — the
    /// embedded skill and instructions text is folded into it — so this
    /// reads in growing chunks until it finds the line's end, capped well
    /// above anything seen in practice.
    public static func cwd(of transcript: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        let chunkSize = 65536
        let maxBytes = 8 * 1024 * 1024
        while data.count < maxBytes {
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            data.append(chunk)
            if chunk.contains(0x0A) { break }
        }
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        guard let firstLine = text.split(separator: "\n", maxSplits: 1).first,
              let lineData = firstLine.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              obj["type"] as? String == "session_meta",
              let payload = obj["payload"] as? [String: Any]
        else { return nil }
        return payload["cwd"] as? String
    }

    /// All transcripts under the sessions tree, newest first, matched by cwd.
    public static func recentTranscripts(
        for project: URL, sessionsDir: URL = sessionsDir, limit: Int = 4,
        fileManager: FileManager = .default
    ) -> [ContextTranscriptFile] {
        let target = project.standardizedFileURL.path
        let allFiles = allTranscriptFiles(under: sessionsDir, fileManager: fileManager)
        let matched = allFiles.filter { cwd(of: $0.path) == target }
        let sorted = matched.sorted { $0.modified > $1.modified }
        return Array(sorted.prefix(limit))
    }

    static func allTranscriptFiles(under root: URL, fileManager: FileManager) -> [ContextTranscriptFile] {
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [ContextTranscriptFile] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }
            files.append(ContextTranscriptFile(path: url, modified: mtime))
        }
        return files
    }

    public static func extract(events: [[String: Any]]) -> ContextHarnessPass {
        var pass = ContextHarnessPass()
        var callInputs: [String: [String: Any]] = [:]
        var callAnswered = Set<String>()
        var newest = ""

        for event in events {
            let ts = event["timestamp"] as? String ?? ""
            if !ts.isEmpty, ts > newest { newest = ts }
            guard event["type"] as? String == "response_item",
                  let payload = event["payload"] as? [String: Any],
                  let kind = payload["type"] as? String
            else { continue }

            switch kind {
            case "message":
                for block in payload["content"] as? [[String: Any]] ?? [] {
                    guard let text = block["text"] as? String else { continue }
                    pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                }
            case "custom_tool_call":
                let input = payload["input"] as? String ?? ""
                pass.blobs.append(ContextRefBlob(text: input, timestamp: ts))
                if let callID = payload["call_id"] as? String {
                    callInputs[callID] = ["label": codexCallLabel(payload), "ts": ts]
                }
            case "custom_tool_call_output":
                for block in payload["output"] as? [[String: Any]] ?? [] {
                    guard let text = block["text"] as? String else { continue }
                    pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                }
                if let callID = payload["call_id"] as? String { callAnswered.insert(callID) }
            default:
                continue
            }
        }

        pass.newestTimestamp = newest
        pass.shells = callInputs.compactMap { callID, info in
            guard !callAnswered.contains(callID) else { return nil }
            let ts = info["ts"] as? String
            guard !codexIsStale(ts, newest: newest) else { return nil }
            return ContextEngineResult.Agent(label: (info["label"] as? String) ?? callID, status: "running")
        }
        return pass
    }
}

private func codexCallLabel(_ payload: [String: Any]) -> String {
    let name = payload["name"] as? String ?? "exec"
    let input = payload["input"] as? String ?? ""
    let firstLine = input.split(separator: "\n").first.map(String.init) ?? input
    let text = firstLine.isEmpty ? name : firstLine
    return text.count <= 56 ? text : String(text.prefix(55)) + "…"
}

private let codexStaleAfter: TimeInterval = 6 * 3600

private func codexIsStale(_ started: String?, newest: String) -> Bool {
    guard let started, !started.isEmpty, !newest.isEmpty,
          let began = ContextTimestamp.parse(started), let last = ContextTimestamp.parse(newest)
    else { return false }
    return last.timeIntervalSince(began) > codexStaleAfter
}
