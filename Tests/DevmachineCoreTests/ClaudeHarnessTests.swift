import XCTest
@testable import DevmachineCore

final class ClaudeHarnessTests: XCTestCase {
    private func jsonl(_ lines: [[String: Any]]) -> [[String: Any]] { lines }

    private func write(_ lines: [String], to dir: URL, name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8
        )
    }

    func testSlugReplacesSlashesWithDashes() {
        let slug = ClaudeHarness.slug(for: URL(fileURLWithPath: "/Users/alice/dev/dash"))
        XCTAssertEqual(slug, "-Users-alice-dev-dash")
    }

    func testProjectDirectoriesIncludeWorktreeSuffixedFolders() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectsDir = tmp.appendingPathComponent("projects")
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let base = ClaudeHarness.slug(for: project)
        try FileManager.default.createDirectory(
            at: projectsDir.appendingPathComponent(base), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectsDir.appendingPathComponent(base + "-feature-x"), withIntermediateDirectories: true
        )
        let dirs = ClaudeHarness.projectDirectories(for: project, projectsDir: projectsDir)
        XCTAssertEqual(dirs.count, 2)
        XCTAssertTrue(dirs[1].lastPathComponent.hasSuffix("-feature-x"))
    }

    func testExtractPicksUpTodoWriteLatestList() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "tool_use", "id": "t1", "name": "TodoWrite",
                         "input": ["todos": [["content": "write tests", "status": "pending"]]]],
                    ],
                ] as [String: Any],
            ],
            [
                "timestamp": "2026-01-01T00:01:00Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "tool_use", "id": "t2", "name": "TodoWrite",
                         "input": ["todos": [
                            ["content": "write tests", "status": "completed"],
                            ["content": "ship it", "status": "in_progress"],
                         ]]],
                    ],
                ] as [String: Any],
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        XCTAssertEqual(pass.todoItems.map(\.text), ["write tests", "ship it"])
        XCTAssertEqual(pass.todoItems.map(\.state), ["done", "active"])
    }

    func testExtractPicksUpTaskCreateChecklistOverTodoWrite() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "toolUseResult": ["task": ["id": 1, "subject": "first task"]] as [String: Any],
            ],
            [
                "timestamp": "2026-01-01T00:01:00Z",
                "toolUseResult": [
                    "success": true, "taskId": 1, "statusChange": ["to": "completed"],
                ] as [String: Any],
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        XCTAssertEqual(pass.todoItems, [ContextEngineResult.PlanItem(text: "first task", state: "done")])
    }

    func testExtractFindsGitHubReferenceInAssistantText() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": [
                    "role": "assistant",
                    "content": [["type": "text", "text": "opened https://github.com/acme/dash/pull/3"]],
                ] as [String: Any],
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        XCTAssertEqual(pass.blobs.count, 1)
        XCTAssertTrue(pass.blobs[0].text.contains("acme/dash/pull/3"))
    }

    func testExtractTracksRunningBackgroundShell() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "tool_use", "id": "call1", "name": "Bash",
                         "input": ["command": "make test", "run_in_background": true]],
                        ["type": "tool_result", "tool_use_id": "call1"],
                    ],
                ] as [String: Any],
                "toolUseResult": ["backgroundTaskId": "bg1"] as [String: Any],
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        XCTAssertEqual(pass.shells, [ContextEngineResult.Agent(label: "make test", status: "running")])
    }

    func testExtractDropsShellMarkedDoneByTaskNotification() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "tool_use", "id": "call1", "name": "Bash", "input": ["command": "make test"]],
                        ["type": "tool_result", "tool_use_id": "call1"],
                    ],
                ] as [String: Any],
                "toolUseResult": ["backgroundTaskId": "bg1"] as [String: Any],
            ],
            [
                "timestamp": "2026-01-01T00:02:00Z",
                "content": "<task-id>bg1</task-id> finished",
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        XCTAssertTrue(pass.shells.isEmpty)
    }

    func testExtractTracksDispatchedSubagentWithNoResultAsRunning() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "tool_use", "id": "agent1", "name": "Task",
                         "input": ["description": "audit the branch"]],
                    ],
                ] as [String: Any],
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        XCTAssertEqual(pass.agents, [ContextEngineResult.Agent(label: "audit the branch", status: "running")])
    }

    func testExtractRecordsTouchedMarkdownFile() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "tool_use", "id": "w1", "name": "Write",
                         "input": ["file_path": "/Users/alice/dev/dash/docs/superpowers/plans/x.md",
                                   "content": "irrelevant body"]],
                    ],
                ] as [String: Any],
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        XCTAssertEqual(pass.touchedMarkdown, ["/Users/alice/dev/dash/docs/superpowers/plans/x.md"])
    }

    func testFileBodyContentIsNotScannedForReferences() {
        let events = jsonl([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "tool_use", "id": "w1", "name": "Write",
                         "input": ["file_path": "/tmp/x.txt",
                                   "content": "https://github.com/acme/dash/pull/99"]],
                    ],
                ] as [String: Any],
            ],
        ])
        let pass = ClaudeHarness.extract(events: events)
        let refs = contextExtractRefs(blobs: pass.blobs, defaultRepo: nil, githubHosts: ["github.com"])
        XCTAssertTrue(refs.github.isEmpty)
    }
}
