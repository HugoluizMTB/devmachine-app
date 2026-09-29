import XCTest
@testable import DevmachineCore

private struct StubRunner: CommandRunner {
    let output: String
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { output }
}

final class NativeContextEngineTests: XCTestCase {
    private func roots() -> ContextRoots {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ContextRoots(
            claudeProjectsDir: base.appendingPathComponent("claude"),
            codexSessionsDir: base.appendingPathComponent("codex"),
            piSessionsDir: base.appendingPathComponent("pi")
        )
    }

    private func write(_ lines: [[String: Any]], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = try lines.map {
            String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!
        }.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testNoTranscriptProducesAnEmptyStubWithNoHarness() {
        let engine = NativeContextEngine(
            runner: StubRunner(output: ""), resolver: ContextGitHubResolver(runner: StubRunner(output: "")),
            githubHosts: ["github.com"], roots: roots()
        )
        let result = engine.buildContext(cwd: "/Users/alice/dev/nowhere", resolvePRs: false)
        XCTAssertNil(result.harness)
        XCTAssertFalse(result.isClaude)
        XCTAssertNil(result.plan)
        XCTAssertTrue(result.prs.isEmpty)
        XCTAssertTrue(result.links.isEmpty)
    }

    func testEndToEndClaudeTranscriptProducesTodosLinksAndUnresolvedPR() throws {
        let roots = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let slug = ClaudeHarness.slug(for: project)
        let transcript = roots.claudeProjectsDir.appendingPathComponent(slug).appendingPathComponent("s1.jsonl")
        try write([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": ["role": "assistant", "content": [
                    ["type": "text", "text": "tracking https://github.com/acme/dash/pull/4 and https://linear.app/acme/issue/ENG-9"],
                    ["type": "tool_use", "id": "t1", "name": "TodoWrite",
                     "input": ["todos": [["content": "ship it", "status": "in_progress"]]]],
                ]],
            ],
        ], to: transcript)

        let engine = NativeContextEngine(
            runner: StubRunner(output: ""), resolver: ContextGitHubResolver(runner: StubRunner(output: "")),
            githubHosts: ["github.com"], roots: roots
        )
        let result = engine.buildContext(cwd: project.path, resolvePRs: false)

        XCTAssertEqual(result.harness, .claude)
        XCTAssertTrue(result.isClaude)
        XCTAssertEqual(result.plan?.items, [ContextEngineResult.PlanItem(text: "ship it", state: "active")])
        XCTAssertEqual(result.prs.map(\.number), [4])
        XCTAssertEqual(result.prs.first?.state, "open")
        XCTAssertEqual(result.links.map(\.label), ["ENG-9"])
    }

    func testResolvePRsFalseSkipsTheGhSubprocess() throws {
        let roots = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let slug = ClaudeHarness.slug(for: project)
        let transcript = roots.claudeProjectsDir.appendingPathComponent(slug).appendingPathComponent("s1.jsonl")
        try write([
            [
                "timestamp": "2026-01-01T00:00:00Z",
                "message": ["role": "assistant", "content": [
                    ["type": "text", "text": "https://github.com/acme/dash/pull/4"],
                ]],
            ],
        ], to: transcript)

        final class CountingRunner: CommandRunner, @unchecked Sendable {
            var calls = 0
            func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
                calls += 1
                return ""
            }
        }
        let counting = CountingRunner()
        let engine = NativeContextEngine(
            runner: StubRunner(output: ""), resolver: ContextGitHubResolver(runner: counting),
            githubHosts: ["github.com"], roots: roots
        )
        _ = engine.buildContext(cwd: project.path, resolvePRs: false)
        XCTAssertEqual(counting.calls, 0)
    }
}
