import XCTest
@testable import DevmachineCore

final class CodexHarnessTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeRollout(_ lines: [[String: Any]], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let text = try lines.map {
            String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!
        }.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testCwdReadsSessionMetaFirstLine() throws {
        let dir = tempDir()
        let file = dir.appendingPathComponent("rollout-x.jsonl")
        try writeRollout([
            ["type": "session_meta", "payload": ["cwd": "/Users/alice/dev/dash"]],
            ["type": "event_msg", "payload": ["type": "task_started"]],
        ], to: file)
        XCTAssertEqual(CodexHarness.cwd(of: file), "/Users/alice/dev/dash")
    }

    func testRecentTranscriptsMatchesOnlyTheProjectCwd() throws {
        let dir = tempDir()
        let matching = dir.appendingPathComponent("2026/01/01/rollout-a.jsonl")
        let other = dir.appendingPathComponent("2026/01/01/rollout-b.jsonl")
        try writeRollout([["type": "session_meta", "payload": ["cwd": "/Users/alice/dev/dash"]]], to: matching)
        try writeRollout([["type": "session_meta", "payload": ["cwd": "/Users/alice/dev/other"]]], to: other)

        let files = CodexHarness.recentTranscripts(
            for: URL(fileURLWithPath: "/Users/alice/dev/dash"), sessionsDir: dir
        )
        XCTAssertEqual(files.map(\.path.lastPathComponent), ["rollout-a.jsonl"])
    }

    func testExtractScansMessageAndToolCallText() {
        let events: [[String: Any]] = [
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "type": "response_item",
                "payload": [
                    "type": "message",
                    "content": [["type": "input_text", "text": "please fix https://github.com/acme/dash/pull/5"]],
                ],
            ],
            [
                "timestamp": "2026-01-01T00:01:00Z",
                "type": "response_item",
                "payload": [
                    "type": "custom_tool_call", "call_id": "c1", "name": "exec",
                    "input": "cmd: gh pr view 5",
                ],
            ],
            [
                "timestamp": "2026-01-01T00:02:00Z",
                "type": "response_item",
                "payload": ["type": "custom_tool_call_output", "call_id": "c1", "output": [["type": "input_text", "text": "ok"]]],
            ],
        ]
        let pass = CodexHarness.extract(events: events)
        let refs = contextExtractRefs(blobs: pass.blobs, defaultRepo: "acme/dash", githubHosts: ["github.com"])
        XCTAssertEqual(refs.github["acme/dash#5"]?.count, 2)
        XCTAssertTrue(pass.shells.isEmpty)
    }

    func testExtractTracksToolCallWithNoOutputAsRunning() {
        let events: [[String: Any]] = [
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "type": "response_item",
                "payload": ["type": "custom_tool_call", "call_id": "c1", "name": "exec", "input": "sleep 999"],
            ],
        ]
        let pass = CodexHarness.extract(events: events)
        XCTAssertEqual(pass.shells.map(\.label), ["sleep 999"])
        XCTAssertEqual(pass.shells.map(\.status), ["running"])
    }
}
