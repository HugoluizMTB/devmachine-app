import SQLite3
import XCTest
@testable import DevmachineCore

private struct SilentRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

final class ContextHarnessReadersTests: XCTestCase {
    private let pr = "https://github.com/acme/widgets/pull/42"
    private let ghCommand = "gh pr view 42"

    private func reader(_ harness: HarnessID, home: URL) throws -> any ContextHarnessReader {
        try XCTUnwrap(ContextRoots(home: home).readers.first { $0.harness == harness })
    }

    private func only(_ reader: any ContextHarnessReader, file: StaticString = #filePath, line: UInt = #line)
        throws -> ContextHarnessPass {
        let transcripts = reader.recentTranscripts(
            for: ContextFixtureHome.widgets, limit: 4, fileManager: .default)
        XCTAssertEqual(transcripts.count, 1, file: file, line: line)
        return reader.pass(for: try XCTUnwrap(transcripts.first, file: file, line: line))
    }

    private func assertNamesThePR(_ pass: ContextHarnessPass, file: StaticString = #filePath, line: UInt = #line) {
        let texts = pass.blobs.map(\.text)
        XCTAssertTrue(texts.contains { $0.contains(pr) }, "PR URL", file: file, line: line)
        XCTAssertTrue(texts.contains { $0.contains(ghCommand) }, "gh command", file: file, line: line)
        XCTAssertFalse(pass.blobs.contains { $0.timestamp.isEmpty }, file: file, line: line)
        let refs = contextExtractRefs(blobs: pass.blobs, defaultRepo: "acme/widgets", githubHosts: ["github.com"])
        XCTAssertNotNil(refs.github["acme/widgets#42"], file: file, line: line)
    }

    private func engine(home: URL) -> NativeContextEngine {
        NativeContextEngine(
            runner: SilentRunner(), resolver: ContextGitHubResolver(runner: SilentRunner()),
            githubHosts: ["github.com"], roots: ContextRoots(home: home))
    }

    func testEveryHarnessWithAReaderIsInTheTable() {
        XCTAssertEqual(
            ContextRoots(home: URL(fileURLWithPath: "/tmp")).readers.map(\.harness),
            [.claude, .codex, .pi, .opencode, .kimi, .cline, .antigravity])
        XCTAssertEqual(
            ContextRoots.supportedHarnesses, [.claude, .codex, .pi, .opencode, .kimi, .cline, .antigravity])
    }

    func testOpencodeReadsTheProjectsTopLevelSessionFromTheDatabase() throws {
        let home = try ContextFixtureHome.copy("opencode")
        let reader = try reader(.opencode, home: home)
        let pass = try only(reader)

        assertNamesThePR(pass)
        XCTAssertEqual(pass.todoItems, [
            ContextEngineResult.PlanItem(text: "Check the PR", state: "active"),
            ContextEngineResult.PlanItem(text: "Run the tests", state: "pending"),
        ])
        XCTAssertEqual(pass.agents, [ContextEngineResult.Agent(label: "Review PR diff", status: "running")])
        XCTAssertEqual(pass.newestTimestamp, "2026-10-02T21:51:38.000Z")
        XCTAssertTrue(reader.recentTranscripts(
            for: ContextFixtureHome.gadgets, limit: 4, fileManager: .default).isEmpty)
    }

    func testOpencodeSeesRowsStillInTheWriteAheadLogWhileAWriterHoldsTheDatabase() throws {
        let home = try ContextFixtureHome.copy("opencode")
        let path = home.appendingPathComponent(".local/share/opencode/opencode.db").path
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &writer), SQLITE_OK)
        defer { sqlite3_close(writer) }
        XCTAssertEqual(sqlite3_exec(writer, "PRAGMA journal_mode=WAL", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(writer, """
            INSERT INTO todo (session_id, content, status, priority, position, time_created, time_updated)
            VALUES ('ses_f01662699ffeFixtureAAAAAA', 'Merge it', 'pending', 'low', 2, 0, 0)
            """, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)

        let pass = try only(try reader(.opencode, home: home))

        XCTAssertEqual(pass.todoItems.last?.text, "Merge it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "-wal"))
        XCTAssertEqual(sqlite3_exec(writer, "ROLLBACK", nil, nil, nil), SQLITE_OK)
    }

    func testOpencodeWithoutADatabaseHasNoSessions() throws {
        let reader = try reader(.opencode, home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertTrue(reader.recentTranscripts(for: ContextFixtureHome.widgets, limit: 4, fileManager: .default).isEmpty)
    }

    func testKimiWorkdirKeyMatchesTheCLIs() {
        XCTAssertEqual(KimiHarness.workdirKey(for: "/Users/alice/dev/widgets"), "wd_widgets_7b506ce63f89")
        XCTAssertEqual(KimiHarness.workdirKey(for: "/Users/me/Developer/proj"), "wd_proj_76bfce3667dc")
        XCTAssertEqual(KimiHarness.workdirKey(for: "/Users/me/Developer/proj/"), "wd_proj_76bfce3667dc")
        XCTAssertTrue(KimiHarness.workdirKey(for: "/").hasPrefix("wd_workspace_"))
    }

    func testKimiFindsTheSessionThroughTheIndexAndReadsItsWire() throws {
        let home = try ContextFixtureHome.copy("kimi")
        let reader = try reader(.kimi, home: home)
        let pass = try only(reader)

        assertNamesThePR(pass)
        XCTAssertEqual(pass.todoItems, [
            ContextEngineResult.PlanItem(text: "Address review comments on PR 42", state: "active"),
            ContextEngineResult.PlanItem(text: "Re-run CI after fixes", state: "pending"),
        ])
        XCTAssertTrue(pass.agents.isEmpty)
        XCTAssertEqual(pass.newestTimestamp, "2026-10-02T14:06:45.611Z")
        XCTAssertTrue(reader.recentTranscripts(
            for: ContextFixtureHome.gadgets, limit: 4, fileManager: .default).isEmpty)
    }

    func testKimiFallsBackToTheComputedFolderWithoutAnIndex() throws {
        let home = try ContextFixtureHome.copy("kimi")
        try FileManager.default.removeItem(at: home.appendingPathComponent(".kimi-code/session_index.jsonl"))
        XCTAssertNoThrow(try only(try reader(.kimi, home: home)))
    }

    func testKimiDropsADeletedSession() throws {
        let home = try ContextFixtureHome.copy("kimi")
        let index = home.appendingPathComponent(".kimi-code/session_index.jsonl")
        let deleted = #"{"sessionId":"session_3f6c1a52-8d1e-4b7a-9c2e-5a1b7d9e0f42","deleted":true}"#
        try (try String(contentsOf: index, encoding: .utf8) + deleted + "\n").write(to: index, atomically: true, encoding: .utf8)

        let reader = try reader(.kimi, home: home)
        XCTAssertTrue(reader.recentTranscripts(for: ContextFixtureHome.widgets, limit: 4, fileManager: .default).isEmpty)
    }

    func testKimiShowsASubagentWithNoEndAsRunning() {
        let pass = KimiHarness.extract(events: [
            ["type": "subagent.spawned", "subagentId": "agent-0", "description": "Read the diff", "time": 1_790_950_000_000],
            ["type": "subagent.spawned", "subagentId": "agent-1", "description": "Run tests", "time": 1_790_950_000_100],
            ["type": "subagent.completed", "subagentId": "agent-1", "time": 1_790_950_000_200],
        ])
        XCTAssertEqual(pass.agents, [ContextEngineResult.Agent(label: "Read the diff", status: "running")])
    }

    func testClineFindsTheSessionInTheIndexAndReadsItsMessages() throws {
        let home = try ContextFixtureHome.copy("cline")
        let reader = try reader(.cline, home: home)
        let pass = try only(reader)

        assertNamesThePR(pass)
        XCTAssertTrue(pass.todoItems.isEmpty)
        XCTAssertTrue(pass.agents.isEmpty)
        XCTAssertEqual(pass.newestTimestamp, "2026-10-01T14:00:09.800Z")
        XCTAssertTrue(reader.recentTranscripts(
            for: ContextFixtureHome.gadgets, limit: 4, fileManager: .default).isEmpty)
    }

    func testClineFallsBackToTheManifestsWithoutTheIndex() throws {
        let home = try ContextFixtureHome.copy("cline")
        try FileManager.default.removeItem(at: home.appendingPathComponent(".cline/data/db"))
        assertNamesThePR(try only(try reader(.cline, home: home)))
    }

    func testClineReadsABareMessageArray() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try #"[{"role":"user","ts":1790863200150,"content":"see https://github.com/acme/widgets/pull/42"}]"#
            .write(to: file, atomically: true, encoding: .utf8)
        let pass = ClineHarness.extract(messages: ClineHarness.messages(at: file))
        XCTAssertEqual(pass.blobs.map(\.text), ["see https://github.com/acme/widgets/pull/42"])
    }

    func testAntigravityFindsTheConversationThroughThePromptLog() throws {
        let home = try ContextFixtureHome.copy("antigravity")
        let reader = try reader(.antigravity, home: home)
        let pass = try only(reader)

        assertNamesThePR(pass)
        XCTAssertTrue(pass.blobs.contains { $0.text == "What is the status of PR 42?" })
        XCTAssertFalse(pass.blobs.contains { $0.text.contains("ADDITIONAL_METADATA") })
        XCTAssertTrue(pass.todoItems.isEmpty)
        XCTAssertEqual(pass.newestTimestamp, "2026-09-30T14:00:06.000Z")
        XCTAssertTrue(reader.recentTranscripts(
            for: ContextFixtureHome.gadgets, limit: 4, fileManager: .default).isEmpty)
    }

    func testAntigravityReadsOnlyTheTailOfALongPromptLog() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ("first line that is cut\n" + "second\n" + "third\n").write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(AntigravityHarness.tailLines(of: file, maxBytes: 12), ["third"])
        XCTAssertEqual(AntigravityHarness.tailLines(of: file, maxBytes: 1000).count, 3)
    }

    func testTheEngineReportsEachHarnessWithItsPullRequest() throws {
        for (name, harness) in [("opencode", HarnessID.opencode), ("kimi", .kimi), ("cline", .cline), ("antigravity", .antigravity)] {
            let home = try ContextFixtureHome.copy(name)
            let result = engine(home: home).buildContext(cwd: ContextFixtureHome.widgets.path, resolvePRs: false)
            XCTAssertEqual(result.harness, harness, name)
            XCTAssertEqual(result.prs.map(\.number), [42], name)

            let elsewhere = engine(home: home).buildContext(cwd: ContextFixtureHome.gadgets.path, resolvePRs: false)
            XCTAssertNil(elsewhere.harness, name)
        }
    }

    func testTheEngineShowsTheHarnessTodosAsThePlan() throws {
        let home = try ContextFixtureHome.copy("kimi")
        let result = engine(home: home).buildContext(cwd: ContextFixtureHome.widgets.path, resolvePRs: false)
        XCTAssertEqual(result.plan?.source, "todos")
        XCTAssertEqual(result.plan?.items.count, 2)
    }
}
