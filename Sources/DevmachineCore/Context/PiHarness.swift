import Foundation

/// Pi transcript discovery and extraction:
/// `~/.pi/agent/sessions/<cwd-slug>/<timestamp>_<id>.jsonl`.
///
/// Each line is `{"type": "message", "message": {"role": "user"|"assistant"|"toolResult", ...}}`
/// (plus `session`, `model_change`, `thinking_level_change` lines this
/// engine has no use for). An assistant message's `content` holds `text` and
/// `toolCall` blocks; a `toolResult` message answers one `toolCall` by its id.
public enum PiHarness {
    public static let sessionsDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".pi/agent/sessions")

    /// Mirrors the Pi CLI's own encoding (`session-manager.js`):
    /// `--${cwd without its leading slash, with /\: turned into -}--`.
    public static func slug(for project: URL) -> String {
        var path = project.standardizedFileURL.path
        if path.hasPrefix("/") { path.removeFirst() }
        let encoded = path.map { c -> Character in
            (c == "/" || c == "\\" || c == ":") ? "-" : c
        }
        return "--" + String(encoded) + "--"
    }

    public static func recentTranscripts(
        for project: URL, sessionsDir: URL = sessionsDir, limit: Int = 4,
        fileManager: FileManager = .default
    ) -> [ContextTranscriptFile] {
        let dir = sessionsDir.appendingPathComponent(slug(for: project))
        return ContextTranscriptDiscovery.recent(in: [dir], glob: "*.jsonl", limit: limit, fileManager: fileManager)
    }

    public static func extract(events: [[String: Any]]) -> ContextHarnessPass {
        var pass = ContextHarnessPass()
        var toolCalls: [String: (label: String, ts: String)] = [:]
        var answered = Set<String>()
        var newest = ""

        for event in events {
            guard event["type"] as? String == "message", let message = event["message"] as? [String: Any]
            else { continue }
            let ts = event["timestamp"] as? String ?? ""
            if !ts.isEmpty, ts > newest { newest = ts }
            let role = message["role"] as? String ?? ""

            switch role {
            case "user", "assistant":
                for block in message["content"] as? [[String: Any]] ?? [] {
                    switch block["type"] as? String {
                    case "text":
                        let text = block["text"] as? String ?? ""
                        pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                    case "toolCall":
                        let name = block["name"] as? String ?? ""
                        let args = block["arguments"]
                        if let argsData = try? JSONSerialization.data(withJSONObject: args ?? [:], options: [.sortedKeys]),
                           let argsText = String(data: argsData, encoding: .utf8) {
                            pass.blobs.append(ContextRefBlob(text: argsText, timestamp: ts))
                        }
                        if name == "subagent", let id = block["id"] as? String {
                            let label = piLabel(args as? [String: Any])
                            toolCalls[id] = (label: label, ts: ts)
                        }
                    default:
                        continue
                    }
                }
            case "toolResult":
                for block in message["content"] as? [[String: Any]] ?? [] {
                    guard let text = block["text"] as? String else { continue }
                    pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                }
                if let callID = message["toolCallId"] as? String { answered.insert(callID) }
            default:
                continue
            }
        }

        pass.newestTimestamp = newest
        pass.agents = toolCalls.compactMap { id, info in
            guard !answered.contains(id), !piIsStale(info.ts, newest: newest) else { return nil }
            return ContextEngineResult.Agent(label: info.label.isEmpty ? id : info.label, status: "running")
        }
        return pass
    }
}

private func piLabel(_ args: [String: Any]?, limit: Int = 56) -> String {
    for key in ["task", "prompt", "description"] {
        guard let value = args?[key] as? String else { continue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return firstLine.count <= limit ? firstLine : String(firstLine.prefix(limit - 1)) + "…"
    }
    return ""
}

private let piStaleAfter: TimeInterval = 6 * 3600

private func piIsStale(_ started: String?, newest: String) -> Bool {
    guard let started, !started.isEmpty, !newest.isEmpty,
          let began = ContextTimestamp.parse(started), let last = ContextTimestamp.parse(newest)
    else { return false }
    return last.timeIntervalSince(began) > piStaleAfter
}
