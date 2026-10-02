import Foundation

/// Cline CLI 3.x indexes its sessions in SQLite, `~/.cline/data/db/sessions.db`
/// (one row per session with the folder it ran in), and keeps each
/// conversation as one JSON file, `sessions/<id>/<id>.messages.json`, with
/// Anthropic-style messages stamped in epoch milliseconds. It has no todo list.
public struct ClineHarness: ContextHarnessReader {
    public let harness = HarnessID.cline
    public let dataDir: URL

    public init(dataDir: URL) {
        self.dataDir = dataDir
    }

    public static func defaultDataDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let data = environment["CLINE_DATA_DIR"], !data.isEmpty { return URL(fileURLWithPath: data) }
        if let config = environment["CLINE_DIR"], !config.isEmpty {
            return URL(fileURLWithPath: config).appendingPathComponent("data")
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cline/data")
    }

    var database: URL { dataDir.appendingPathComponent("db/sessions.db") }
    var sessionsDir: URL { dataDir.appendingPathComponent("sessions") }

    public func recentTranscripts(for project: URL, limit: Int, fileManager: FileManager) -> [ContextTranscriptFile] {
        let cwd = project.standardizedFileURL.path
        let sessions: [(id: String, messages: String?)]
        if let db = ContextSQLite(path: database) {
            sessions = db.rows("""
                SELECT session_id, messages_path FROM sessions
                WHERE (cwd = ? OR workspace_root = ?) AND is_subagent = 0
                  AND (parent_session_id IS NULL OR parent_session_id = '')
                ORDER BY started_at DESC LIMIT ?
                """, [cwd, cwd, String(max(limit, 1) * 4)]
            ).compactMap { row in row.text("session_id").map { ($0, row.text("messages_path")) } }
        } else {
            sessions = manifestSessions(for: cwd, fileManager: fileManager)
        }
        let files = sessions.compactMap { session -> ContextTranscriptFile? in
            let recorded = session.messages.map(URL.init(fileURLWithPath:))
            let local = sessionsDir.appendingPathComponent(session.id)
                .appendingPathComponent("\(session.id).messages.json")
            let path = recorded.flatMap { fileManager.fileExists(atPath: $0.path) ? $0 : nil } ?? local
            guard let modified = contextModified(path) else { return nil }
            return ContextTranscriptFile(path: path, modified: modified, session: session.id)
        }
        return contextRecent(files, limit: limit)
    }

    /// Without the index (it failed to open), each session's manifest
    /// still names its folder.
    private func manifestSessions(for cwd: String, fileManager: FileManager) -> [(id: String, messages: String?)] {
        let dirs = (try? fileManager.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            let id = dir.lastPathComponent
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(id).json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  manifest["cwd"] as? String == cwd || manifest["workspace_root"] as? String == cwd
            else { return nil }
            return (id, manifest["messages_path"] as? String)
        }
    }

    public func pass(for transcript: ContextTranscriptFile) -> ContextHarnessPass {
        var pass = Self.extract(messages: Self.messages(at: transcript.path))
        if let session = transcript.session, let db = ContextSQLite(path: database) {
            pass.agents = db.rows("""
                SELECT session_id, agent_id, prompt FROM sessions
                WHERE parent_session_id = ? AND status IN ('idle', 'running', 'pending')
                ORDER BY started_at
                """, [session]
            ).map { row in
                let label = contextLabel(row.text("prompt"))
                return ContextEngineResult.Agent(
                    label: label.isEmpty ? (row.text("agent_id") ?? row.text("session_id") ?? "agent") : label,
                    status: "running")
            }
        }
        return pass
    }

    /// The file is rewritten in place, not swapped in, so a read can meet
    /// it half written: one more try before giving up on this poll.
    static func messages(at path: URL) -> [[String: Any]] {
        for _ in 0..<2 {
            guard let data = try? Data(contentsOf: path) else { return [] }
            if let object = try? JSONSerialization.jsonObject(with: data) {
                if let wrapped = object as? [String: Any] { return wrapped["messages"] as? [[String: Any]] ?? [] }
                return object as? [[String: Any]] ?? []
            }
        }
        return []
    }

    public static func extract(messages: [[String: Any]]) -> ContextHarnessPass {
        var pass = ContextHarnessPass()
        var newest = ""
        for message in messages {
            let ts = (message["ts"] as? Double).map { contextISO(milliseconds: $0) } ?? ""
            if ts > newest { newest = ts }
            if let text = message["content"] as? String {
                pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                continue
            }
            for block in message["content"] as? [[String: Any]] ?? [] {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
                case "tool_use":
                    if let text = contextJSONText(block["input"]) { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
                case "tool_result":
                    if let text = clineResultText(block["content"]) {
                        pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                    }
                default:
                    continue
                }
            }
        }
        pass.newestTimestamp = newest
        return pass
    }
}

private func clineResultText(_ content: Any?) -> String? {
    if let text = content as? String { return text }
    guard let items = content as? [[String: Any]] else { return nil }
    let texts = items.flatMap { item in
        ["text", "query", "result", "error"].compactMap { item[$0] as? String }
    }
    return texts.isEmpty ? nil : texts.joined(separator: "\n")
}
