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
    private func makeStore(_ box: SnapshotBox, runner: FakePrepareRunner = FakePrepareRunner()) -> MachineReadinessStore {
        MachineReadinessStore(read: { box.read() }, runner: runner, listensForReports: false)
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

    func testPrepareAddsThenSyncsOnlyThePackageAndRefreshes() async {
        let box = SnapshotBox(snapshot(declared: ["main": false], applied: false))
        let runner = FakePrepareRunner()
        runner.lines = ["PLAY RECAP", "main : ok=3 changed=1 failed=0"]
        runner.onRun = { arguments in
            if arguments.first == "sync" { box.current = snapshot(stamp: "2") }
        }
        let store = makeStore(box, runner: runner)
        var prepared: [String] = []
        store.onPrepared = { prepared.append($0) }
        await store.check()
        XCTAssertEqual(store.state(for: "main"), .notDeclared)

        await store.prepare("main")

        XCTAssertEqual(runner.calls, [
            ["packages", "add", "devmachine-app", "--machine", "main", "--yes"],
            ["sync", "--machine", "main", "--tags", "devmachine-app", "--yes"],
        ])
        XCTAssertEqual(store.jobs["main"]?.phase, .succeeded)
        XCTAssertTrue(store.jobs["main"]?.output.contains("main : ok=3 changed=1 failed=0") ?? false)
        XCTAssertEqual(store.state(for: "main"), .ready)
        XCTAssertEqual(prepared, ["main"])
    }

    func testPrepareSkipsTheAddWhenAlreadyDeclared() async {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let runner = FakePrepareRunner()
        runner.onRun = { _ in box.current = snapshot(stamp: "2") }
        let store = makeStore(box, runner: runner)
        await store.check()

        await store.prepare("main")

        XCTAssertEqual(runner.calls, [["sync", "--machine", "main", "--tags", "devmachine-app", "--yes"]])
    }

    func testAFailedSyncShowsTheExactErrorAndTheWholeLog() async {
        let box = SnapshotBox(snapshot(declared: ["main": true], applied: false))
        let runner = FakePrepareRunner()
        runner.statuses = [1]
        runner.lines = ["TASK [devmachine-app]", "error: 1 task(s) failed on main: exit status 2"]
        let store = makeStore(box, runner: runner)
        var prepared: [String] = []
        store.onPrepared = { prepared.append($0) }
        await store.check()

        await store.prepare("main")

        guard case let .failed(error) = store.jobs["main"]?.phase else {
            return XCTFail("expected a failure, got \(String(describing: store.jobs["main"]))")
        }
        XCTAssertEqual(error.cause, "1 task(s) failed on main: exit status 2")
        XCTAssertTrue(error.details.contains("TASK [devmachine-app]"))
        XCTAssertTrue(error.details.contains("$ devmachine sync --machine main --tags devmachine-app --yes"))
        XCTAssertEqual(prepared, [])
    }

    func testAnOldCLINeverRunsPrepare() async {
        let runner = FakePrepareRunner()
        let store = makeStore(SnapshotBox(snapshot(declared: ["main": true], applied: false, version: "0.7.23")), runner: runner)
        await store.check()
        XCTAssertFalse(store.canPrepareInApp)

        await store.prepare("main")

        XCTAssertEqual(runner.calls, [])
        XCTAssertNil(store.jobs["main"])
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
        XCTAssertFalse(model.isPollingPaused)
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
            MachineReadinessContent.title(machine: "main", state: .notApplied, job: nil),
            "main isn't ready for the app yet")
        XCTAssertEqual(
            MachineReadinessContent.title(machine: "main", state: .outdated(detail: ""), job: nil),
            "main's devmachine-app package is out of date")
        XCTAssertEqual(
            MachineReadinessContent.title(machine: "main", state: .notApplied, job: PrepareJob(phase: .running, output: [])),
            "Preparing main…")
    }

    func testTheSidebarLineForEachRun() {
        XCTAssertEqual(MachineReadinessContent.compactLine(machine: "main", phase: .running), "Preparing main…")
        XCTAssertEqual(MachineReadinessContent.compactLine(machine: "main", phase: .succeeded), "main is ready")
        XCTAssertEqual(
            MachineReadinessContent.compactLine(
                machine: "main", phase: .failed(DMErrorState(title: "x", cause: nil, details: ""))),
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
            read: { next }, runner: ProcessJobRunner(cli: { throw DevmachineCLIError.commandFailed("no") }),
            listensForReports: false)

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
