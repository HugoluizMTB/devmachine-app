import XCTest
import DevmachineCore
@testable import DevmachineApp

/// A CLI that answers `scheduled` by subcommand: `runs` walks through
/// `runReplies`, one per call, and stays on the last.
private final class ScheduledFakeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    var list = ""
    var runReplies: [String] = []
    var saveStderr = ""
    var saveStdout = ""
    var saveExitCode: Int32 = 0
    var syncStderr = ""
    var syncExitCode: Int32 = 0
    private(set) var syncArgs: [String] = []
    private(set) var listCalls = 0
    private var runsCalls = 0

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        defer { lock.unlock() }
        if args.contains("list") {
            listCalls += 1
            return (list, "", 0)
        }
        if args.contains("harnesses") { return (#"{"harnesses":[]}"#, "", 0) }
        if args.contains("run") { return (#"{"workspace":"alice","task":"t_1","run_id":"r2"}"#, "", 0) }
        if args.contains("runs") {
            let reply = runReplies[min(runsCalls, runReplies.count - 1)]
            runsCalls += 1
            return (reply, "", 0)
        }
        if args.contains("add") { return (saveStdout, saveStderr, saveExitCode) }
        if args.contains("sync") {
            syncArgs = args
            return ("", syncStderr, syncExitCode)
        }
        return ("", "", 0)
    }
}

@MainActor
final class ScheduledStoreTests: XCTestCase {
    private static func task(lastRun: String) -> String {
        """
        {"version":1,"id":"t_1","name":"Nightly","paused":false,"done":false,"folder":"~/app",\
        "schedule":{"every":"daily","at":"02:00","timezone":"UTC"},"action":{"kind":"command","command":"make"},\
        "next_run_at":"2026-10-17T02:00:00Z","last_run":\(lastRun)}
        """
    }

    private static func run(_ id: String, _ status: String, _ at: String) -> String {
        #"{"id":"\#(id)","task_id":"t_1","status":"\#(status)","trigger":"manual","started_at":"\#(at)","duration_ms":0}"#
    }

    private static let oldRun = run("r1", "succeeded", "2026-10-15T02:00:00Z")
    private static let newRun = run("r2", "running", "2026-10-16T16:05:00Z")
    private static let endedRun = run("r2", "failed", "2026-10-16T16:05:00Z")

    private func makeStore(_ runner: ScheduledFakeRunner) -> ScheduledStore {
        ScheduledStore(
            makeCLI: { DevmachineCLI(executable: "/x", runner: runner) },
            pollInterval: .milliseconds(20))
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testRunNowShowsTheRunOnTheRowWhileItRunsAndWhenItEnds() async {
        let runner = ScheduledFakeRunner()
        runner.list = #"{"workspaces":[{"name":"alice","machine":"main","installed":true,"tasks":[\#(Self.task(lastRun: Self.oldRun))]}]}"#
        runner.runReplies = [
            #"{"runs":[\#(Self.newRun),\#(Self.oldRun)]}"#,
            #"{"runs":[\#(Self.newRun),\#(Self.oldRun)]}"#,
            #"{"runs":[\#(Self.endedRun),\#(Self.oldRun)]}"#,
        ]
        let store = makeStore(runner)
        store.refresh()
        await waitUntil { store.rows.count == 1 }
        let row = store.rows[0]
        XCTAssertEqual(store.lastRun(row)?.id, "r1")

        store.runNow(row)

        await waitUntil { store.lastRun(row)?.status == .running }
        XCTAssertEqual(store.lastRun(row)?.id, "r2")
        await waitUntil { store.lastRun(row)?.status == .failed }
    }

    func testTheRowStillShowsTheRunWhenTheListIsStale() async {
        let runner = ScheduledFakeRunner()
        runner.list = #"{"workspaces":[{"name":"alice","machine":"main","installed":true,"tasks":[\#(Self.task(lastRun: "null"))]}]}"#
        runner.runReplies = [#"{"runs":[\#(Self.endedRun)]}"#]
        let store = makeStore(runner)
        store.refresh()
        await waitUntil { store.rows.count == 1 }
        let row = store.rows[0]
        XCTAssertNil(store.lastRun(row))

        store.runNow(row)

        await waitUntil { store.lastRun(row)?.status == .failed }
        await waitUntil { runner.listCalls >= 2 }
        XCTAssertEqual(store.lastRun(store.rows[0])?.id, "r2")
    }

    func testSettingUpAWorkspaceReportsTheCLIsSteps() async throws {
        let runner = ScheduledFakeRunner()
        runner.list = #"{"workspaces":[{"name":"alice","machine":"main","installed":false,"tasks":[]}]}"#
        runner.saveStderr = "added scheduled to workspace alice\nPLAY [main] ****\nTASK [scheduled : Install] ****\n"
        runner.saveStdout = #"{"workspace":"alice","task":\#(Self.task(lastRun: "null"))}"#
        let store = makeStore(runner)
        var seen: [ScheduledSetupProgress.Phase] = []
        let watch = store.$setup.sink { if let phase = $0?.phase, seen.last != phase { seen.append(phase) } }
        defer { watch.cancel() }
        var draft = ScheduledDraft(workspace: "alice", timezone: "UTC")
        draft.name = "Nightly"
        draft.folder = "~/app"
        draft.command = "make"

        let saved = try await store.save(draft, editing: nil, allowDangerous: false, settingUpOn: "main")

        XCTAssertEqual(saved.id, "t_1")
        XCTAssertEqual(seen, [.addingPackage, .connecting, .installing])
        XCTAssertNil(store.setup)
    }

    func testSavingOnAReadyWorkspaceShowsNoSetup() async throws {
        let runner = ScheduledFakeRunner()
        runner.saveStdout = #"{"workspace":"alice","task":\#(Self.task(lastRun: "null"))}"#
        let store = makeStore(runner)
        var shown = false
        let watch = store.$setup.sink { if $0 != nil { shown = true } }
        defer { watch.cancel() }
        var draft = ScheduledDraft(workspace: "alice", timezone: "UTC")
        draft.name = "Nightly"
        draft.folder = "~/app"
        draft.command = "make"

        _ = try await store.save(draft, editing: nil, allowDangerous: false, settingUpOn: nil)

        XCTAssertFalse(shown)
    }

    private static let failedSetupStderr = """
    added scheduled to workspace alice
    PLAY [main] ****
    TASK [scheduled : Unpack the release] ****
    fatal: [main]: FAILED! => {"msg": "Failed to find handler"}
    error: setting up scheduled on main failed: 1 task(s) failed on main, first "scheduled : Unpack the release": Failed to find handler
    """

    func testAFailedSetupThrowsTheCLIsErrorAndReadsTheListAgain() async throws {
        let runner = ScheduledFakeRunner()
        runner.list = #"{"workspaces":[{"name":"alice","machine":"main","installed":false,"tasks":[]}]}"#
        runner.saveStderr = Self.failedSetupStderr
        runner.saveExitCode = 1
        let store = makeStore(runner)
        var draft = ScheduledDraft(workspace: "alice", timezone: "UTC")
        draft.name = "Nightly"
        draft.folder = "~/app"
        draft.command = "make"

        do {
            _ = try await store.save(draft, editing: nil, allowDangerous: false, settingUpOn: "main")
            XCTFail("a failed setup was reported as saved")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                #"setting up scheduled on main failed: 1 task(s) failed on main, first "scheduled : Unpack the release": Failed to find handler"#)
        }
        XCTAssertNil(store.setup)
        await waitUntil { runner.listCalls >= 1 }
    }

    func testFinishingASetupSyncsTheMachineForScheduledOnly() async {
        let runner = ScheduledFakeRunner()
        runner.list = #"{"workspaces":[{"name":"alice","machine":"main","installed":false,"tasks":[],"error":{"kind":"setup-incomplete","message":"m"}}]}"#
        let store = makeStore(runner)
        store.refresh()
        await waitUntil { store.workspaces.count == 1 }
        let calls = runner.listCalls

        store.finishSetup(store.workspaces[0])

        await waitUntil { runner.listCalls > calls }
        XCTAssertEqual(runner.syncArgs, ["--format", "json", "sync", "--machine", "main", "--tags", "scheduled", "--yes"])
        XCTAssertNil(store.setupErrors["alice"])
        XCTAssertNil(store.setup)
    }

    func testAFailedFinishKeepsTheCLIsErrorOnTheWorkspace() async {
        let runner = ScheduledFakeRunner()
        runner.list = #"{"workspaces":[{"name":"alice","machine":"main","installed":false,"tasks":[],"error":{"kind":"setup-incomplete","message":"m"}}]}"#
        runner.syncStderr = "PLAY [main] ****\nerror: 1 task(s) failed on main, first \"scheduled : Unpack the release\": nope\n"
        runner.syncExitCode = 1
        let store = makeStore(runner)
        store.refresh()
        await waitUntil { store.workspaces.count == 1 }

        store.finishSetup(store.workspaces[0])

        await waitUntil { store.setupErrors["alice"] != nil }
        XCTAssertEqual(store.setupErrors["alice"], #"1 task(s) failed on main, first "scheduled : Unpack the release": nope"#)
    }
}
