import Foundation

/// Claude Code transcript discovery and extraction: `~/.claude/projects/<slug>/*.jsonl`.
public enum ClaudeHarness {
    public static let projectsDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/projects")

    public static func slug(for project: URL) -> String {
        project.standardizedFileURL.path.replacingOccurrences(of: "/", with: "-")
    }

    /// The project's own transcript dir, plus the dirs of worktree sessions
    /// spawned under it (`<slug>-<worktree-branch>`): a session that moves
    /// into a git worktree writes to another slug while the tmux pane stays
    /// in the repository root.
    public static func projectDirectories(
        for project: URL, projectsDir: URL = projectsDir, fileManager: FileManager = .default
    ) -> [URL] {
        let base = slug(for: project)
        var dirs = [projectsDir.appendingPathComponent(base)]
        if let entries = try? fileManager.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) {
            let worktreeDirs = entries
                .filter { $0.lastPathComponent.hasPrefix(base + "-") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            dirs.append(contentsOf: worktreeDirs)
        }
        return dirs
    }

    public static func recentTranscripts(
        for project: URL, projectsDir: URL = projectsDir, limit: Int = 4,
        fileManager: FileManager = .default
    ) -> [ContextTranscriptFile] {
        ContextTranscriptDiscovery.recent(
            in: projectDirectories(for: project, projectsDir: projectsDir, fileManager: fileManager),
            glob: "*.jsonl", limit: limit, fileManager: fileManager
        )
    }

    static func stringContent(_ message: [String: Any]) -> [String]? {
        guard let content = message["content"] else { return nil }
        if let s = content as? String { return [s] }
        return nil
    }

    static func blocks(_ message: [String: Any]) -> [[String: Any]] {
        message["content"] as? [[String: Any]] ?? []
    }

    public static func extract(events: [[String: Any]]) -> ContextHarnessPass {
        var pass = ContextHarnessPass()
        var tools: [String: [String: Any]] = [:]
        var resultIDs = Set<String>()
        var finishedTaskIDs = Set<String>()
        var monitors: [String: String] = [:]
        var shells: [String: String] = [:]
        var subagents: [String: String] = [:]
        var dispatches: [String: [String: Any]] = [:]
        var started: [String: String] = [:]
        var newest = ""

        var taskChecklist: [String: [String: Any]] = [:]
        var taskOrder: [String] = []
        var todoWriteLatest: [[String: Any]]?

        for event in events {
            let ts = event["timestamp"] as? String ?? ""
            if !ts.isEmpty, ts > newest { newest = ts }

            if let text = event["content"] as? String {
                finishedTaskIDs.formUnion(contextFindTaskIDs(in: text))
            }
            if let attachment = event["attachment"] as? [String: Any] {
                for field in ["prompt", "text"] {
                    if let s = attachment[field] as? String {
                        finishedTaskIDs.formUnion(contextFindTaskIDs(in: s))
                    }
                }
            }
            let toolUseResult = event["toolUseResult"] as? [String: Any]
            if let taskID = toolUseResult?["task_id"] as? String {
                finishedTaskIDs.insert(taskID)
            }

            if let created = toolUseResult?["task"] as? [String: Any], let id = created["id"] {
                let key = "\(id)"
                taskChecklist[key] = ["text": created["subject"] as? String ?? "", "state": "pending"]
                taskOrder.append(key)
            } else if toolUseResult?["success"] as? Bool == true,
                      let taskID = toolUseResult?["taskId"], var task = taskChecklist["\(taskID)"],
                      let to = (toolUseResult?["statusChange"] as? [String: Any])?["to"] as? String {
                task["state"] = claudeTodoState(to)
                taskChecklist["\(taskID)"] = task
            }

            guard let message = event["message"] as? [String: Any] else { continue }

            if let s = stringContent(message)?.first {
                finishedTaskIDs.formUnion(contextFindTaskIDs(in: s))
                pass.blobs.append(ContextRefBlob(text: s, timestamp: ts))
                continue
            }

            for block in blocks(message) {
                guard let kind = block["type"] as? String else { continue }
                switch kind {
                case "text":
                    let text = block["text"] as? String ?? ""
                    finishedTaskIDs.formUnion(contextFindTaskIDs(in: text))
                    pass.blobs.append(ContextRefBlob(text: text, timestamp: ts))
                case "tool_use":
                    let input = block["input"] as? [String: Any] ?? [:]
                    var scan = input
                    scan.removeValue(forKey: "content")
                    scan.removeValue(forKey: "new_string")
                    scan.removeValue(forKey: "old_string")
                    if let scanData = try? JSONSerialization.data(withJSONObject: scan, options: [.sortedKeys]),
                       let scanText = String(data: scanData, encoding: .utf8) {
                        pass.blobs.append(ContextRefBlob(text: scanText, timestamp: ts))
                    }
                    let name = block["name"] as? String ?? ""
                    if let fp = input["file_path"] as? String, ["Write", "Edit"].contains(name), fp.hasSuffix(".md") {
                        pass.touchedMarkdown.append(fp)
                    }
                    if let id = block["id"] as? String {
                        tools[id] = input
                        if ["Task", "Agent"].contains(name) { dispatches[id] = input }
                    }
                    if name == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
                        todoWriteLatest = todos
                    }
                case "tool_result":
                    if let tuid = block["tool_use_id"] as? String { resultIDs.insert(tuid) }
                    guard let res = toolUseResult else { continue }
                    let tuid = block["tool_use_id"] as? String ?? ""
                    let input = tools[tuid] ?? [:]
                    if let bgID = res["backgroundTaskId"] as? String {
                        shells[bgID] = claudeTaskLabel(input, keys: ["description", "command"])
                        started[bgID] = ts
                    } else if let monitorID = res["taskId"], res["timeoutMs"] != nil {
                        let key = "\(monitorID)"
                        monitors[key] = claudeTaskLabel(input, keys: ["description", "command"])
                        started[key] = ts
                    } else if res["isAsync"] as? Bool == true, let agentID = res["agentId"] as? String {
                        subagents[agentID] = (res["description"] as? String)
                            ?? claudeTaskLabel(input, keys: ["description", "subagent_type", "prompt"])
                        started[agentID] = ts
                    }
                default:
                    continue
                }
            }
        }

        pass.newestTimestamp = newest

        if !taskOrder.isEmpty {
            pass.todoItems = taskOrder.compactMap { key in
                guard let t = taskChecklist[key] else { return nil }
                return ContextEngineResult.PlanItem(
                    text: t["text"] as? String ?? "", state: t["state"] as? String ?? "pending"
                )
            }
        } else if let todos = todoWriteLatest {
            pass.todoItems = todos.map {
                ContextEngineResult.PlanItem(
                    text: $0["content"] as? String ?? "",
                    state: claudeTodoState($0["status"] as? String ?? "")
                )
            }
        }

        func stillRunning(_ group: [String: String]) -> [ContextEngineResult.Agent] {
            group.compactMap { key, label in
                guard !finishedTaskIDs.contains(key), !claudeIsStale(started[key], newest: newest) else { return nil }
                return ContextEngineResult.Agent(label: label.isEmpty ? key : label, status: "running")
            }
        }

        var agents = stillRunning(subagents)
        for (id, input) in dispatches where !resultIDs.contains(id) {
            let label = claudeTaskLabel(input, keys: ["description", "subagent_type", "prompt"])
            agents.append(ContextEngineResult.Agent(label: label.isEmpty ? id : label, status: "running"))
        }
        pass.agents = agents
        pass.monitors = stillRunning(monitors)
        pass.shells = stillRunning(shells)

        return pass
    }
}

private let claudeTodoStateMap: [String: String] = [
    "completed": "done", "in_progress": "active", "pending": "pending",
]

private func claudeTodoState(_ raw: String) -> String {
    claudeTodoStateMap[raw] ?? "pending"
}

private func claudeTaskLabel(_ input: [String: Any], keys: [String], limit: Int = 56) -> String {
    for key in keys {
        guard let value = input[key] as? String else { continue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return firstLine.count <= limit ? firstLine : String(firstLine.prefix(limit - 1)) + "…"
    }
    return ""
}

/// A notification can go missing — the session ends, the app restarts, the
/// harness drops it. Without a cutoff that task spins in the panel forever.
private let claudeStaleAfter: TimeInterval = 6 * 3600

private func claudeIsStale(_ started: String?, newest: String) -> Bool {
    guard let started, !started.isEmpty, !newest.isEmpty,
          let began = ContextTimestamp.parse(started), let last = ContextTimestamp.parse(newest)
    else { return false }
    return last.timeIntervalSince(began) > claudeStaleAfter
}
