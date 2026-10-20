import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ReadinessRunner: CommandRunner, @unchecked Sendable {
    var config = #"{"machines":[{"name":"main"},{"name":"beta"},{"name":"mac","self":true}],"#
        + #""workspaces":[{"name":"acme","machine":"main","user":"acme"},{"name":"gamma","machine":"beta","user":"gamma"}],"domain":"example.com"}"#
    var packages: (String, String, Int32) =
        (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine main","machine beta"]}]}"#, "", 0)
    var version = "devmachine 0.7.24\n"
    var aliases = #"{"aliases":[],"written":false,"ssh_aliases":true}"#

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        if args.contains("show") { return (config, "", 0) }
        if args.contains("packages") { return packages }
        if args.contains("path") { return (#"{"path":"/Users/alice/.config/devmachine","source":"default"}"#, "", 0) }
        if args.contains("version") { return (version, "", 0) }
        if args.contains("aliases") { return (aliases, "", 0) }
        return ("", "not stubbed: \(args)", 1)
    }
}

private let lockWithMainOnly = """
    applied_at: "2026-09-18T12:00:00Z"
    machines:
        beta:
            - name: base
        main:
            - name: devmachine-app
              version: v0.7.3
    """

final class ReadinessReaderTests: XCTestCase {
    private func read(_ runner: ReadinessRunner, lock: LockFileRead = .text(lockWithMainOnly)) -> ReadinessSnapshot? {
        ReadinessReader.read(
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) },
            readLock: { directory in
                XCTAssertEqual(directory, "/Users/alice/.config/devmachine")
                return lock
            })
    }

    func testReadsDeclaredFromTheConfigurationAndAppliedFromTheLock() throws {
        let snapshot = try XCTUnwrap(read(ReadinessRunner()))
        XCTAssertEqual(snapshot.machines, ["main", "beta"])
        XCTAssertEqual(snapshot.declared, ["main": true, "beta": true])
        XCTAssertEqual(snapshot.applied("main"), true)
        XCTAssertEqual(snapshot.applied("beta"), false)
        XCTAssertEqual(snapshot.workspaceMachines, ["acme": "main", "gamma": "beta"])
        XCTAssertEqual(snapshot.cliVersion, SemanticVersion("0.7.24"))
        XCTAssertEqual(snapshot.sshAliasesWritten, true)
        XCTAssertEqual(snapshot.configDirectory, "/Users/alice/.config/devmachine")
    }

    func testAMissingLockMeansNothingWasEverApplied() throws {
        let snapshot = try XCTUnwrap(read(ReadinessRunner(), lock: .missing))
        XCTAssertEqual(snapshot.applied("main"), false)
    }

    func testAnUnreadableLockSaysNothing() throws {
        let snapshot = try XCTUnwrap(read(ReadinessRunner(), lock: .unreadable))
        XCTAssertNil(snapshot.applied("main"))
    }

    func testAFailedPackagesReadLeavesDeclaredUnknown() throws {
        let runner = ReadinessRunner()
        runner.packages = ("", "connection refused", 1)
        let snapshot = try XCTUnwrap(read(runner))
        XCTAssertNil(snapshot.declared)
    }

    func testReadsTheCLIsOwnOutputWithNoDomainAndAPackageNoRecipeProvides() throws {
        let runner = ReadinessRunner()
        runner.config = #"{"machines":[{"name":"main","hosts":["203.0.113.10"],"admin_user":"root","port":22,"#
            + #""workspaces":["acme"]}],"workspaces":[{"name":"acme","machine":"main","user":"acme"}]}"#
        runner.packages = (#"{"packages":[{"name":"devmachine-app","source":"missing","installed_on":["machine main"]}]}"#, "", 0)
        runner.aliases = ""
        let snapshot = try XCTUnwrap(read(runner, lock: .missing))
        XCTAssertEqual(snapshot.declared, ["main": true])
        XCTAssertEqual(snapshot.applied("main"), false)
        XCTAssertNil(snapshot.sshAliasesWritten)
    }

    func testEachMachineCarriesItsLoginEntry() throws {
        let runner = ReadinessRunner()
        runner.config = #"{"machines":[{"name":"main","hosts":["203.0.113.7"],"admin_user":"alice","port":22,"#
            + #""key":"/Users/alice/.ssh/main"},{"name":"beta","hosts":["100.64.0.2"],"admin_user":"bob","port":2222}],"#
            + #""workspaces":[],"domain":"example.com"}"#
        let snapshot = try XCTUnwrap(read(runner))
        XCTAssertEqual(snapshot.machineLogins, [
            "main": "203.0.113.7|alice|22|/Users/alice/.ssh/main|",
            "beta": "100.64.0.2|bob|2222||",
        ])
    }

    func testNoCLIIsNoSnapshot() {
        XCTAssertNil(ReadinessReader.read(cli: { throw DevmachineCLIError.executableNotFound([]) }))
    }
}

private final class FakePrepareRunner: MachineJobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var statuses: [Int32] = []
    var lines: [String] = []
    var onRun: (@Sendable ([String]) -> Void)?

    var calls: [[String]] { lock.withLock { recorded } }

    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let status: Int32 = lock.withLock {
            recorded.append(arguments)
            return statuses.isEmpty ? 0 : statuses.removeFirst()
        }
        for line in lines { output(line) }
        onRun?(arguments)
        return status
    }
}

private final class SlowFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var on: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ReadinessSnapshot?
    private var reads = 0

    init(_ value: ReadinessSnapshot?) { self.value = value }

    var current: ReadinessSnapshot? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }

    func read() -> ReadinessSnapshot? {
        lock.withLock {
            reads += 1
            return value
        }
    }

    var readCount: Int { lock.withLock { reads } }
}

private func snapshot(
    declared: [String: Bool]? = ["main": true],
    applied: Bool = true,
    stamp: String = "1",
    version: String = "0.7.24"
) -> ReadinessSnapshot {
    var snapshot = ReadinessSnapshot()
    snapshot.machines = ["main"]
    snapshot.declared = declared
    snapshot.lock = PackagesLock(
        appliedAt: stamp,
        machines: ["main": applied ? [PackagesLock.Entry(name: "devmachine-app")] : []])
    snapshot.workspaceMachines = ["acme": "main"]
    snapshot.cliVersion = SemanticVersion(version)
    return snapshot
}

@MainActor
final class MachineReadinessStoreTests: XCTestCase {
    private func makeStore(_ box: SnapshotBox, center: MachineJobCenter? = nil) -> MachineReadinessStore {
        MachineReadinessStore(read: { box.read() }, jobs: { center }, listensForReports: false)
    }

    func testStatesComeFromTheSnapshot() async {
        let store = makeStore(SnapshotBox(snapshot(declared: ["main": true], applied: false)))
        await store.check()
        XCTAssertEqual(store.state(for: "main"), .notApplied)
        XCTAssertEqual(store.machinesNeedingAttention, ["main"])

        let ready = makeStore(SnapshotBox(snapshot()))
        await ready.check()
        XCTAssertEqual(ready.state(for: "main"), .ready)
        XCTAssertEqual(ready.machinesNeedingAttention, [])
    }

    func testNothingReadFailsOpen() async {
        let store = makeStore(SnapshotBox(nil))
        await store.check()
        XCTAssertEqual(store.state(for: "main"), .unknown)
        XCTAssertEqual(store.machinesNeedingAttention, [])
    }

    func testAFailedCallMarksTheMachineAndChecksAgain() async throws {
        let box = SnapshotBox(snapshot())
        let store = makeStore(box)
        await store.check()

        store.observe(.init(
            machine: nil, workspace: "acme",
            detail: #"error: devmachine-app does not accept "context". It accepts stats"#))

        guard case .outdated = store.state(for: "main") else {
            return XCTFail("expected outdated, got \(store.state(for: "main"))")
        }
        try await waitFor { box.readCount == 2 }
        guard case .outdated = store.state(for: "main") else {
            return XCTFail("a check with the same lock must keep what the call said")
        }
    }

    func testANewSyncInTheLockClearsWhatACallSaid() async {
        let box = SnapshotBox(snapshot())
        let store = makeStore(box)
        await store.check()
        store.observe(.init(machine: "main", workspace: nil, detail: "devmachine-app is not installed on main. Add it"))
        XCTAssertEqual(store.state(for: "main"), .notApplied)

        box.current = snapshot(stamp: "2")
        await store.check()
        XCTAssertEqual(store.state(for: "main"), .ready)
    }

    func testAnUnrelatedErrorChangesNothing() async {
        let store = makeStore(SnapshotBox(snapshot()))
        await store.check()
        store.observe(.init(machine: "main", workspace: nil, detail: "ssh: connect to host main port 22: Connection refused"))
        XCTAssertEqual(store.state(for: "main"), .ready)
    }

    func testPrepareAddsThenSyncsOnlyThePackageAsACornerJobAndRefreshes() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": false], applied: false))
        let runner = FakePrepareRunner()
        runner.lines = ["PLAY RECAP", "main : ok=3 changed=1 failed=0"]
        runner.onRun = { arguments in
            if arguments.first == "sync" { box.current = snapshot(stamp: "2") }
        }
        let center = MachineJobCenter(runner: runner, successSeconds: 60)
        let store = makeStore(box, center: center)
        var prepared: [String] = []
        store.onPrepared = { prepared.append($0) }
        await store.check()
        XCTAssertEqual(store.state(for: "main"), .notDeclared)

        let id = try XCTUnwrap(store.prepare("main"))

        XCTAssertEqual(store.preparing["main"], id)
        XCTAssertEqual(store.prepareStatus("main"), .running)
        XCTAssertEqual(center.job(id)?.plan.title, "Prepare main")
        try await waitFor { prepared == ["main"] }
        XCTAssertEqual(runner.calls, [
            ["packages", "add", "devmachine-app", "--machine", "main", "--yes"],
            ["sync", "--machine", "main", "--tags", "devmachine-app", "--yes"],
        ])
        XCTAssertTrue(center.job(id)?.log.lines.contains("main : ok=3 changed=1 failed=0") ?? false)
        XCTAssertEqual(store.prepareStatus("main"), .succeeded)
        XCTAssertEqual(store.state(for: "main"), .ready)
        XCTAssertEqual(store.machinesNeedingAttention, ["main"], "the finished job stays until the corner lets it go")

        store.dismissPrepare("main")
        XCTAssertNil(center.job(id))
        XCTAssertNil(store.preparing["main"])
        XCTAssertEqual(store.machinesNeedingAttention, [])
    }

    func testAPrepareJobThatLeavesTheCornerLeavesTheCard() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let runner = FakePrepareRunner()
        runner.onRun = { _ in box.current = snapshot(stamp: "2") }
        let center = MachineJobCenter(runner: runner, successSeconds: 0)
        let store = makeStore(box, center: center)
        var prepared: [String] = []
        store.onPrepared = { prepared.append($0) }
        await store.check()

        store.prepare("main")

        try await waitFor { store.preparing["main"] == nil && prepared == ["main"] }
        XCTAssertNil(store.prepareStatus("main"))
        XCTAssertEqual(store.machinesNeedingAttention, [])
    }

    func testASlowCheckStillReportsAfterTheCardLeftTheCorner() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let slow = SlowFlag()
        let runner = FakePrepareRunner()
        runner.onRun = { _ in
            box.current = snapshot(stamp: "2")
            slow.on = true
        }
        let center = MachineJobCenter(runner: runner, successSeconds: 0)
        let store = MachineReadinessStore(
            read: {
                if slow.on { try? await Task.sleep(nanoseconds: 200_000_000) }
                return box.read()
            },
            jobs: { center }, listensForReports: false)
        var prepared: [String] = []
        store.onPrepared = { prepared.append($0) }
        await store.check()

        store.prepare("main")

        try await waitFor { store.preparing["main"] == nil }
        XCTAssertEqual(prepared, [], "the check is still reading when the card leaves")
        try await waitFor { prepared == ["main"] }
        XCTAssertEqual(store.state(for: "main"), .ready)
    }

    func testAMachineThatBecomesReadyDropsTheStillNotReadyFailure() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let center = MachineJobCenter(runner: FakePrepareRunner(), successSeconds: 60)
        let store = makeStore(box, center: center)
        await store.check()
        store.prepare("main")
        try await waitFor { store.prepareFailure["main"] != nil }

        box.current = snapshot(stamp: "2")
        await store.check()

        XCTAssertNil(store.prepareFailure["main"])
        XCTAssertEqual(store.prepareStatus("main"), .succeeded)
    }

    func testPrepareSkipsTheAddWhenAlreadyDeclared() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let runner = FakePrepareRunner()
        runner.onRun = { _ in box.current = snapshot(stamp: "2") }
        let center = MachineJobCenter(runner: runner, successSeconds: 60)
        let store = makeStore(box, center: center)
        await store.check()

        store.prepare("main")

        try await waitFor { store.prepareStatus("main") == .succeeded }
        XCTAssertEqual(runner.calls, [["sync", "--machine", "main", "--tags", "devmachine-app", "--yes"]])
    }

    func testASecondPrepareWhileOneRunsStartsNothing() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let runner = FakePrepareRunner()
        let center = MachineJobCenter(runner: runner, successSeconds: 60)
        let store = makeStore(box, center: center)
        await store.check()

        let first = store.prepare("main")
        let second = store.prepare("main")

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(center.jobs.count, 1)
        let id = try XCTUnwrap(first)
        try await waitFor { center.job(id)?.phase != .running(step: 0) }
    }

    func testAFailedSyncLeavesTheCornerJobFailedAndTheCardShowsItsCauseThenARetrySucceeds() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let runner = FakePrepareRunner()
        runner.statuses = [1]
        runner.lines = ["TASK [devmachine-app]", "error: 1 task(s) failed on main: exit status 2"]
        let center = MachineJobCenter(runner: runner, successSeconds: 60)
        let store = makeStore(box, center: center)
        var prepared: [String] = []
        store.onPrepared = { prepared.append($0) }
        await store.check()

        let id = try XCTUnwrap(store.prepare("main"))

        try await waitFor { if case .failed = center.job(id)?.phase { return true } else { return false } }
        XCTAssertEqual(center.job(id)?.phase, .failed(cause: "1 task(s) failed on main: exit status 2"))
        XCTAssertEqual(store.prepareStatus("main"), .failed(DMErrorState(
            title: "main was not prepared", cause: "1 task(s) failed on main: exit status 2", details: ""),
            inCorner: true))
        XCTAssertEqual(store.machinesNeedingAttention, ["main"])
        XCTAssertEqual(prepared, [])

        store.showPrepareInCorner("main")
        store.showPrepareInCorner("main")
        XCTAssertEqual(center.job(id)?.expanded, true)

        runner.lines = []
        runner.onRun = { _ in box.current = snapshot(stamp: "2") }
        store.retryPrepare("main")

        try await waitFor { prepared == ["main"] }
        XCTAssertEqual(store.preparing["main"], id)
        XCTAssertEqual(store.prepareStatus("main"), .succeeded)
        XCTAssertEqual(store.state(for: "main"), .ready)
    }

    func testASyncThatLeavesTheMachineUnreadySaysSo() async throws {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let runner = FakePrepareRunner()
        let center = MachineJobCenter(runner: runner, successSeconds: 60)
        let store = makeStore(box, center: center)
        var prepared: [String] = []
        store.onPrepared = { prepared.append($0) }
        await store.check()

        store.prepare("main")

        try await waitFor { store.prepareFailure["main"] != nil }
        let failure = DMErrorState(
            title: "main still isn't ready",
            cause: "The sync finished, but the configuration does not show devmachine-app applied there.",
            details: "")
        XCTAssertEqual(store.prepareFailure["main"], failure)
        XCTAssertEqual(store.prepareStatus("main"), .failed(failure, inCorner: false))
        XCTAssertEqual(prepared, [])
        XCTAssertEqual(store.machinesNeedingAttention, ["main"])
    }

    func testAnOldCLINeverRunsPrepare() async {
        let runner = FakePrepareRunner()
        let center = MachineJobCenter(runner: runner)
        let store = makeStore(
            SnapshotBox(snapshot(declared: ["main": true], applied: false, version: "0.7.23")), center: center)
        await store.check()
        XCTAssertFalse(store.canPrepareInApp)

        XCTAssertNil(store.prepare("main"))

        XCTAssertEqual(runner.calls, [])
        XCTAssertTrue(center.jobs.isEmpty)
        XCTAssertNil(store.preparing["main"])
    }

    func testCheckingWhenActiveIsThrottled() async {
        let box = SnapshotBox(snapshot())
        let store = makeStore(box)
        await store.check()
        store.requestCheckIfStale(now: Date().addingTimeInterval(5))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(box.readCount, 1)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

final class PackageCallReportTests: XCTestCase {
    private struct FailingRunner: CommandRunner {
        let stderr: String
        func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
        func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
            -> (stdout: String, stderr: String, exitCode: Int32) { ("", stderr, 1) }
    }

    func testAFailedPackageCallIsAnnouncedWithItsMachine() {
        let cli = DevmachineCLI(
            executable: "/opt/devmachine",
            runner: FailingRunner(stderr: "error: devmachine-app is not installed on main."))
        let expectation = expectation(forNotification: PackageCallReports.notification, object: nil) { notification in
            PackageCallReports.report(from: notification)
                == .init(machine: "main", workspace: nil, detail: "error: devmachine-app is not installed on main.")
        }
        XCTAssertThrowsError(try cli.run(machine: "main", package: "devmachine-app", args: ["stats"]))
        wait(for: [expectation], timeout: 1)
    }

    func testAWorkspaceContextCallIsAnnouncedWithItsWorkspace() {
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: FailingRunner(stderr: "boom"))
        let expectation = expectation(forNotification: PackageCallReports.notification, object: nil) { notification in
            PackageCallReports.report(from: notification)?.workspace == "acme"
        }
        XCTAssertThrowsError(try cli.context(workspace: "acme", session: "dash"))
        wait(for: [expectation], timeout: 1)
    }
}

final class SessionProblemTests: XCTestCase {
    func testAMissingAliasSaysWhichCommandWritesIt() {
        let problem = SessionProblem(SessionListError(problem: .aliasMissing(alias: "acme-devmachine"), stderr: ""))
        let shown = problem.presentation(workspace: "acme")
        XCTAssertEqual(shown.title, "acme has no SSH alias yet")
        XCTAssertEqual(shown.commands, ["devmachine aliases --write"])
    }

    func testNoTmux() {
        let problem = SessionProblem(SessionListError(problem: .tmuxMissing, stderr: ""))
        XCTAssertEqual(problem, .tmuxMissing(detail: ""))
        XCTAssertEqual(problem.presentation(workspace: "acme").title, "tmux isn't installed for acme")
    }

    func testAWorkspaceAwaitingItsSyncSaysWhichCommandCreatesTheAccount() {
        let problem = SessionProblem.awaitingSync(detail: "beta@203.0.113.7: Permission denied (publickey).")
        let shown = problem.presentation(workspace: "beta")
        XCTAssertEqual(shown.title, "beta isn't set up on its machine yet")
        XCTAssertEqual(shown.commands, ["devmachine sync"])
        XCTAssertEqual(shown.details, "beta@203.0.113.7: Permission denied (publickey).")
    }

    func testAWorkspaceAndItsMachineAwaitingTheFirstSyncAreOneCard() {
        let problem = SessionProblem.awaitingSync(detail: "beta@203.0.113.7: Permission denied (publickey).")
        let shown = problem.firstSyncPresentation(workspace: "beta", machine: "main")
        XCTAssertEqual(shown.title, "main needs its first sync")
        XCTAssertEqual(shown.commands, ["devmachine sync --machine main"])
        XCTAssertEqual(shown.details, "beta@203.0.113.7: Permission denied (publickey).")
        XCTAssertTrue(shown.cause?.contains("beta") == true)
    }

    func testOnlyADeclaredButUnsyncedPackageAndANewWorkspaceShareACard() {
        let awaiting = SessionProblem.awaitingSync(detail: "")
        XCTAssertTrue(SessionProblem.mergesIntoFirstSync(state: .notApplied, status: nil, problem: awaiting))
        XCTAssertFalse(SessionProblem.mergesIntoFirstSync(state: .notDeclared, status: nil, problem: awaiting))
        XCTAssertFalse(SessionProblem.mergesIntoFirstSync(state: .notApplied, status: nil, problem: nil))
        XCTAssertFalse(SessionProblem.mergesIntoFirstSync(
            state: .notApplied, status: nil, problem: .unreachable(detail: "")))
        XCTAssertFalse(SessionProblem.mergesIntoFirstSync(
            state: .outdated(detail: ""), status: nil, problem: awaiting))
        XCTAssertFalse(SessionProblem.mergesIntoFirstSync(state: .ready, status: nil, problem: awaiting))
        XCTAssertFalse(SessionProblem.mergesIntoFirstSync(state: .notApplied, status: .running, problem: awaiting))
    }

    func testSSHFailuresKeepTheirExactText() {
        let refused = SessionProblem(SessionStoreError(failure: .authDenied, stderr: "Permission denied (publickey)."))
        XCTAssertEqual(refused.presentation(workspace: "acme").details, "Permission denied (publickey).")
        let unreachable = SessionProblem(SessionStoreError(
            failure: .unreachable, stderr: "ssh: connect to host 203.0.113.7 port 22: Connection refused"))
        XCTAssertEqual(unreachable.presentation(workspace: "acme").cause, FailureCause.unreachable.summary)
    }
}

private struct ExitRunner: CommandRunner {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { stdout }
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) { (stdout, stderr, exitCode) }
}

@MainActor
final class SessionProblemModelTests: XCTestCase {
    private func model(_ runner: ExitRunner) -> AppModel {
        let model = AppModel(store: SessionStore(runner: runner))
        model.settings = AppSettings(
            opsRepoPath: "/tmp", hostAlias: "devmachine", publicIP: "203.0.113.10", baseDomain: "example.com")
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        return model
    }

    func testAFailedListShowsWhyInsteadOfAnEmptyList() async throws {
        let model = model(ExitRunner(
            stdout: "", stderr: "ssh: Could not resolve hostname acme-devmachine: nodename nor servname provided",
            exitCode: 255))

        model.refresh(alias: "acme-devmachine")

        try await waitFor { model.sessionProblems["acme-devmachine"] != nil }
        XCTAssertEqual(model.sessionProblems["acme-devmachine"], .aliasMissing(alias: "acme-devmachine"))
        XCTAssertFalse(model.offlineAliases.contains("acme-devmachine"))
        XCTAssertFalse(model.isPollingPaused(alias: "acme-devmachine"))
    }

    func testAListThatAnswersClearsTheProblem() async throws {
        let failing = model(ExitRunner(stdout: "@@PANES@@\n", stderr: "", exitCode: 127))
        failing.refresh(alias: "acme-devmachine")
        try await waitFor { failing.sessionProblems["acme-devmachine"] != nil }
        XCTAssertEqual(failing.sessionProblems["acme-devmachine"], .tmuxMissing(detail: ""))
    }

    func testNoTmuxServerIsAnEmptyListNotAProblem() async throws {
        let model = model(ExitRunner(stdout: "@@PANES@@\n", stderr: "no server running", exitCode: 1))
        model.refresh(alias: "acme-devmachine")
        try await waitFor { model.sessionsByAlias["acme-devmachine"] != nil }
        XCTAssertNil(model.sessionProblems["acme-devmachine"])
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

final class MachineReadinessContentTests: XCTestCase {
    func testTitles() {
        XCTAssertEqual(
            MachineReadinessContent.title(machine: "main", state: .notApplied, status: nil),
            "main isn't ready for the app yet")
        XCTAssertEqual(
            MachineReadinessContent.title(machine: "main", state: .outdated(detail: ""), status: nil),
            "main's devmachine-app package is out of date")
        XCTAssertEqual(
            MachineReadinessContent.title(machine: "main", state: .notApplied, status: .running),
            "Preparing main…")
        XCTAssertEqual(MachineReadinessContent.preparingBody, "Preparing… the card in the corner shows the log")
    }

    func testTheSidebarLineForEachRun() {
        XCTAssertEqual(MachineReadinessContent.compactLine(machine: "main", status: .running), "Preparing main…")
        XCTAssertEqual(MachineReadinessContent.compactLine(machine: "main", status: .succeeded), "main is ready")
        XCTAssertEqual(
            MachineReadinessContent.compactLine(
                machine: "main", status: .failed(DMErrorState(title: "x", cause: nil, details: ""), inCorner: true)),
            "Prepare failed")
    }

    func testCommandsToCopy() {
        XCTAssertEqual(
            MachineReadinessContent.commands(machine: "main", state: .notDeclared, declared: false),
            ["devmachine packages add devmachine-app --machine main", "devmachine sync --machine main"])
        XCTAssertEqual(
            MachineReadinessContent.commands(machine: "main", state: .outdated(detail: ""), declared: true),
            ["devmachine packages pin", "devmachine sync --machine main"])
    }

    func testTheOldCLITextNamesTheVersionItNeeds() {
        XCTAssertTrue(MachineReadinessContent.oldCLIBody.contains("0.7.24"))
    }
}

@MainActor
final class ConfigDirectoryWatcherTests: XCTestCase {
    func testAFolderThatDoesNotExistYetIsWatchedOnceItDoes() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("devmachine-watch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var snapshot = ReadinessSnapshot()
        snapshot.configDirectory = folder.path
        let next = snapshot
        let store = MachineReadinessStore(
            read: { next }, jobs: { nil }, listensForReports: false)

        await store.check()
        XCTAssertFalse(store.isWatchingConfiguration, "nothing to watch before setup writes the folder")

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await store.check()
        XCTAssertTrue(store.isWatchingConfiguration)
    }

    func testASaveByRenameIsSeenOnce() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("devmachine-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("machines: []\n".utf8).write(to: folder.appendingPathComponent("config.yml"))
        var changes = 0
        let watcher = ConfigDirectoryWatcher(directory: folder.path) { changes += 1 }

        let temporary = folder.appendingPathComponent("config.yml.tmp")
        try Data("machines: [main]\n".utf8).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(folder.appendingPathComponent("config.yml"), withItemAt: temporary)
        try Data("applied_at: x\n".utf8).write(to: folder.appendingPathComponent("packages.lock"))

        let deadline = Date().addingTimeInterval(5)
        while changes == 0, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(changes, 1)
        _ = watcher
    }
}
