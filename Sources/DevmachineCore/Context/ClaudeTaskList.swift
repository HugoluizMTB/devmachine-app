import Foundation

/// A Claude Code session's task list: one JSON file per task under
/// `<config dir>/tasks/<session id>/`.
public enum ClaudeTaskList {
    public static func directory(
        sessionID: String, projectsDir: URL, environment: [String: String]
    ) -> URL {
        let config = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? projectsDir.deletingLastPathComponent()
        return config.appendingPathComponent("tasks").appendingPathComponent(sessionID)
    }

    public static func read(
        directory: URL, fileManager: FileManager = .default
    ) -> [ContextEngineResult.PlanItem] {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let tasks = entries.filter { $0.pathExtension == "json" }.compactMap { url -> (Int, String, String)? in
            guard let data = try? Data(contentsOf: url),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let subject = object["subject"] as? String
            else { return nil }
            let id = (object["id"] as? String).flatMap { Int($0) } ?? (object["id"] as? Int)
                ?? Int(url.deletingPathExtension().lastPathComponent)
            guard let id else { return nil }
            return (id, subject, claudeTodoState(object["status"] as? String ?? ""))
        }
        return tasks.sorted { $0.0 < $1.0 }.map { ContextEngineResult.PlanItem(text: $0.1, state: $0.2) }
    }
}
