import Foundation

/// The Antigravity CLI (`agy`) keeps every conversation flat under
/// `~/.gemini/antigravity-cli/brain/<id>/`, with no folder per project; the
/// step log is `.system_generated/logs/transcript_full.jsonl`. Only the
/// prompt log, `history.jsonl`, says which folder a conversation ran in.
/// The format is undocumented and read from what the CLI writes, so every
/// field is optional here.
public struct AntigravityHarness: ContextHarnessReader {
    public let harness = HarnessID.antigravity
    public let dir: URL

    /// The prompt log grows with every prompt ever typed; its tail holds
    /// the conversations that matter.
    static let historyTailBytes = 2 * 1024 * 1024

    public init(dir: URL) {
        self.dir = dir
    }

    public static func defaultDir() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/antigravity-cli")
    }

    public func recentTranscripts(for project: URL, limit: Int, fileManager: FileManager) -> [ContextTranscriptFile] {
        let cwd = project.standardizedFileURL.path
        var seen = Set<String>()
        var files: [ContextTranscriptFile] = []
        for line in Self.tailLines(of: dir.appendingPathComponent("history.jsonl"), maxBytes: Self.historyTailBytes).reversed() {
            guard files.count < limit else { break }
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  entry["workspace"] as? String == cwd,
                  let id = entry["conversationId"] as? String, !id.isEmpty, !id.contains("/"),
                  seen.insert(id).inserted
            else { continue }
            if let file = transcript(for: id) { files.append(file) }
        }
        return contextRecent(files, limit: limit)
    }

    private func transcript(for id: String) -> ContextTranscriptFile? {
        let logs = dir.appendingPathComponent("brain").appendingPathComponent(id)
            .appendingPathComponent(".system_generated/logs")
        for name in ["transcript_full.jsonl", "transcript.jsonl"] {
            let path = logs.appendingPathComponent(name)
            if let modified = contextModified(path) { return ContextTranscriptFile(path: path, modified: modified) }
        }
        return nil
    }

    static func tailLines(of url: URL, maxBytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return [] }
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.filter { !$0.isEmpty }
    }

    public func pass(for transcript: ContextTranscriptFile) -> ContextHarnessPass {
        Self.extract(events: ContextJSONLReader.events(at: transcript.path))
    }

    /// Steps that are neither the user, the model's answer nor a tool's
    /// result.
    private static let skipped: Set<String> = [
        "CONVERSATION_HISTORY", "CHECKPOINT", "EPHEMERAL_MESSAGE", "SYSTEM_MESSAGE", "ERROR_MESSAGE",
    ]

    public static func extract(events: [[String: Any]]) -> ContextHarnessPass {
        var pass = ContextHarnessPass()
        var newest = ""
        for step in events {
            let ts = (step["created_at"] as? String).flatMap(ContextTimestamp.parse).map(contextISO) ?? ""
            if ts > newest { newest = ts }
            guard let type = step["type"] as? String, !skipped.contains(type) else { continue }
            let content = step["content"] as? String ?? ""

            switch type {
            case "USER_INPUT":
                let request = antigravityUserRequest(content)
                if !request.isEmpty { pass.blobs.append(ContextRefBlob(text: request, timestamp: ts)) }
            case "PLANNER_RESPONSE":
                if !content.isEmpty { pass.blobs.append(ContextRefBlob(text: content, timestamp: ts)) }
                for call in step["tool_calls"] as? [[String: Any]] ?? [] {
                    if let text = contextJSONText(call["args"]) { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
                }
            default:
                guard step["source"] as? String == "MODEL", !content.isEmpty else { continue }
                pass.blobs.append(ContextRefBlob(text: content, timestamp: ts))
            }
        }
        pass.newestTimestamp = newest
        return pass
    }
}

/// A prompt step carries the typed text inside `<USER_REQUEST>` followed by
/// metadata the CLI adds (the local time, a settings change).
private func antigravityUserRequest(_ content: String) -> String {
    guard let open = content.range(of: "<USER_REQUEST>") else { return content }
    let rest = content[open.upperBound...]
    let inner = rest.range(of: "</USER_REQUEST>").map { rest[..<$0.lowerBound] } ?? rest
    return inner.trimmingCharacters(in: .whitespacesAndNewlines)
}
