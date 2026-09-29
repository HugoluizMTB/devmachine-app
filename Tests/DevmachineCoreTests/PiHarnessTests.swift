import XCTest
@testable import DevmachineCore

final class PiHarnessTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testSlugWrapsTheEncodedPathInDoubleDashes() {
        let slug = PiHarness.slug(for: URL(fileURLWithPath: "/Users/alice/dev/dash"))
        XCTAssertEqual(slug, "--Users-alice-dev-dash--")
    }

    func testRecentTranscriptsReadTheSlugDirectory() throws {
        let dir = tempDir()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let sessionDir = dir.appendingPathComponent(PiHarness.slug(for: project))
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try "{}".write(to: sessionDir.appendingPathComponent("2026-01-01T00-00-00-000Z_x.jsonl"), atomically: true, encoding: .utf8)

        let files = PiHarness.recentTranscripts(for: project, sessionsDir: dir)
        XCTAssertEqual(files.count, 1)
    }

    func testExtractScansUserAssistantAndToolResultText() {
        let events: [[String: Any]] = [
            [
                "type": "message", "timestamp": "2026-01-01T00:00:00Z",
                "message": ["role": "user", "content": [["type": "text", "text": "check https://github.com/acme/dash/issues/8"]]],
            ],
            [
                "type": "message", "timestamp": "2026-01-01T00:01:00Z",
                "message": ["role": "assistant", "content": [
                    ["type": "toolCall", "id": "call1", "name": "bash", "arguments": ["command": "gh issue view 8"]],
                ]],
            ],
            [
                "type": "message", "timestamp": "2026-01-01T00:02:00Z",
                "message": ["role": "toolResult", "toolCallId": "call1", "toolName": "bash",
                            "content": [["type": "text", "text": "closed"]]],
            ],
        ]
        let pass = PiHarness.extract(events: events)
        let refs = contextExtractRefs(blobs: pass.blobs, defaultRepo: "acme/dash", githubHosts: ["github.com"])
        XCTAssertEqual(refs.github["acme/dash#8"]?.count, 2)
    }

    func testExtractTracksDispatchedSubagentWithNoResultAsRunning() {
        let events: [[String: Any]] = [
            [
                "type": "message", "timestamp": "2026-01-01T00:00:00Z",
                "message": ["role": "assistant", "content": [
                    ["type": "toolCall", "id": "sub1", "name": "subagent",
                     "arguments": ["task": "run the migration"]],
                ]],
            ],
        ]
        let pass = PiHarness.extract(events: events)
        XCTAssertEqual(pass.agents, [ContextEngineResult.Agent(label: "run the migration", status: "running")])
    }

    func testExtractDropsSubagentThatAlreadyAnswered() {
        let events: [[String: Any]] = [
            [
                "type": "message", "timestamp": "2026-01-01T00:00:00Z",
                "message": ["role": "assistant", "content": [
                    ["type": "toolCall", "id": "sub1", "name": "subagent", "arguments": ["task": "run the migration"]],
                ]],
            ],
            [
                "type": "message", "timestamp": "2026-01-01T00:01:00Z",
                "message": ["role": "toolResult", "toolCallId": "sub1", "toolName": "subagent",
                            "content": [["type": "text", "text": "done"]]],
            ],
        ]
        let pass = PiHarness.extract(events: events)
        XCTAssertTrue(pass.agents.isEmpty)
    }
}
