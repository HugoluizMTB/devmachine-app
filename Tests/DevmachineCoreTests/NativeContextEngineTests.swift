import XCTest
@testable import DevmachineCore

private struct StubRunner: CommandRunner {
    let output: String
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { output }
}

final class NativeContextEngineTests: XCTestCase {
    private func roots() -> ContextRoots {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ContextRoots(home: base)
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

    private func engine(roots: ContextRoots) -> NativeContextEngine {
        NativeContextEngine(
            runner: StubRunner(output: ""), resolver: ContextGitHubResolver(runner: StubRunner(output: "")),
            githubHosts: ["github.com"], roots: roots, environment: [:]
        )
    }

    private func planFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Plan\n\n- [ ] write the thing\n- [x] read the thing\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func transcriptTouching(_ plan: URL) -> [[String: Any]] {
        [[
            "timestamp": "2026-01-01T00:00:00Z",
            "message": ["role": "assistant", "content": [
                ["type": "tool_use", "id": "t1", "name": "Write", "input": ["file_path": plan.path, "content": "x"]],
            ]],
        ]]
    }

    func testClaudeSessionTodosComeFromItsTaskFiles() throws {
        let roots = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let transcript = roots.claudeProjectsDir.appendingPathComponent(ClaudeHarness.slug(for: project))
            .appendingPathComponent("s1.jsonl")
        try write(transcriptTouching(try planFile(named: "plan.md")), to: transcript)
        let tasks = roots.claudeProjectsDir.deletingLastPathComponent().appendingPathComponent("tasks/s1")
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try #"{"id":"1","subject":"ship it","status":"in_progress"}"#
            .write(to: tasks.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)

        let result = engine(roots: roots).buildContext(cwd: project.path, resolvePRs: false)

        XCTAssertEqual(result.plan?.source, "todos")
        XCTAssertEqual(result.plan?.items, [ContextEngineResult.PlanItem(text: "ship it", state: "active")])
    }

    func testClaudeSessionWithoutTasksShowsNoPlanFile() throws {
        let roots = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let transcript = roots.claudeProjectsDir.appendingPathComponent(ClaudeHarness.slug(for: project))
            .appendingPathComponent("s1.jsonl")
        try write(transcriptTouching(try planFile(named: "plan.md")), to: transcript)

        let result = engine(roots: roots).buildContext(cwd: project.path, resolvePRs: false)

        XCTAssertEqual(result.harness, .claude)
        XCTAssertNil(result.plan)
    }

    func testNonClaudeHarnessStillShowsAPlanFile() throws {
        let roots = roots()
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let plans = project.appendingPathComponent("docs/superpowers/plans")
        try FileManager.default.createDirectory(at: plans, withIntermediateDirectories: true)
        try "# Plan\n\n- [ ] write the thing\n".write(
            to: plans.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)
        try write([
            ["timestamp": "2026-01-01T00:00:00Z", "type": "session_meta",
             "payload": ["id": "c1", "cwd": project.standardizedFileURL.path]],
        ], to: roots.codexSessionsDir.appendingPathComponent("2026/01/01/rollout-2026-01-01T00-00-00-c1.jsonl"))

        let result = engine(roots: roots).buildContext(cwd: project.path, resolvePRs: false)

        XCTAssertEqual(result.harness, .codex)
        XCTAssertEqual(result.plan?.source, "file")
        XCTAssertEqual(result.plan?.items.map(\.text), ["write the thing"])
    }
}
