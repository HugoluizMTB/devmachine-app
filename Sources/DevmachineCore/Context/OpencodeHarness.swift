import Foundation

/// opencode keeps every session in one SQLite database,
/// `$XDG_DATA_HOME/opencode/opencode.db` (`~/.local/share/opencode` on macOS
/// too): `session` rows hold the directory they ran in, `part` rows hold
/// text and tool calls with their results, and `todo` holds the current list.
public struct OpencodeHarness: ContextHarnessReader {
    public let harness = HarnessID.opencode
    public let dataDir: URL

    public init(dataDir: URL) {
        self.dataDir = dataDir
    }

    public static func defaultDataDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("opencode")
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/opencode")
    }

    var database: URL { dataDir.appendingPathComponent("opencode.db") }

    /// Top-level sessions only: a subagent's session points at its parent.
    public func recentTranscripts(for project: URL, limit: Int, fileManager: FileManager) -> [ContextTranscriptFile] {
        guard let db = ContextSQLite(path: database) else { return [] }
        let rows = db.rows("""
            SELECT id, time_updated FROM session
            WHERE directory = ? AND parent_id IS NULL AND time_archived IS NULL
            ORDER BY time_updated DESC LIMIT ?
            """, [project.standardizedFileURL.path, String(max(limit, 1) * 4)])
        let files = rows.compactMap { row -> ContextTranscriptFile? in
            guard let id = row.text("id"), let updated = row.number("time_updated") else { return nil }
            return ContextTranscriptFile(
                path: database, modified: Date(timeIntervalSince1970: updated / 1000), session: id)
        }
        return contextRecent(files, limit: limit)
    }

    public func pass(for transcript: ContextTranscriptFile) -> ContextHarnessPass {
        guard let session = transcript.session, let db = ContextSQLite(path: transcript.path) else {
            return ContextHarnessPass()
        }
        var pass = ContextHarnessPass()
        var newest = ""
        let parts = db.rows("""
            SELECT p.time_created AS created, p.time_updated AS updated,
                   json_extract(m.data, '$.role') AS role, p.data AS data
            FROM part p JOIN message m ON m.id = p.message_id
            WHERE p.session_id = ? AND json_extract(p.data, '$.type') IN ('text', 'tool')
            ORDER BY m.time_created, m.id, p.id
            """, [session])
        var running: [(label: String, started: String)] = []
        var todoWrite: [[String: Any]]?
        for row in parts {
            guard let raw = row.text("data"), let data = raw.data(using: .utf8),
                  let part = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let ts = contextISO(milliseconds: row.number("created") ?? 0)
            let updated = contextISO(milliseconds: row.number("updated") ?? row.number("created") ?? 0)
            if updated > newest { newest = updated }

            if part["type"] as? String == "text" {
                if part["synthetic"] as? Bool == true { continue }
                if let text = part["text"] as? String { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
                continue
            }
            let state = part["state"] as? [String: Any] ?? [:]
            let input = state["input"] as? [String: Any]
            if let text = contextJSONText(input) { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
            for key in ["output", "error"] {
                if let text = state[key] as? String { pass.blobs.append(ContextRefBlob(text: text, timestamp: ts)) }
            }
            let tool = part["tool"] as? String
            if tool == "todowrite", let todos = input?["todos"] as? [[String: Any]] { todoWrite = todos }
            let status = state["status"] as? String
            if tool == "task", status == "pending" || status == "running" {
                let label = contextLabel((input?["description"] as? String) ?? (input?["prompt"] as? String))
                running.append((label.isEmpty ? "task" : label, ts))
            }
        }

        let todos = db.rows(
            "SELECT content, status FROM todo WHERE session_id = ? ORDER BY position", [session]
        ).map { ($0.text("content") ?? "", $0.text("status") ?? "") }
        let items = todos.isEmpty
            ? (todoWrite ?? []).map { ($0["content"] as? String ?? "", $0["status"] as? String ?? "") }
            : todos
        pass.todoItems = items.map { ContextEngineResult.PlanItem(text: $0.0, state: opencodeTodoState($0.1)) }
        pass.agents = running.filter { !contextIsStale($0.started, newest: newest) }
            .map { ContextEngineResult.Agent(label: $0.label, status: "running") }
        pass.newestTimestamp = newest
        return pass
    }
}

private func opencodeTodoState(_ raw: String) -> String {
    switch raw {
    case "completed", "cancelled": return "done"
    case "in_progress": return "active"
    default: return "pending"
    }
}
