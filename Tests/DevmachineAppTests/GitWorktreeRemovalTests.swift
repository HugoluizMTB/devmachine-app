import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedGitRunner: CommandRunner, @unchecked Sendable {
    typealias Reply = (stdout: String, stderr: String, exitCode: Int32)

    private let lock = NSLock()
    private var sent: [String] = []
    private let snapshot: String
    private let checkAll: String
    private let check: String
    private let remove: Reply

    init(snapshot: String, checkAll: String, check: String, remove: Reply) {
        self.snapshot = snapshot
        self.checkAll = checkAll
        self.check = check
        self.remove = remove
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws -> Reply {
        let command = args.last ?? ""
        lock.lock()
        sent.append(command)
        lock.unlock()
        if command.contains("rev-parse --show-toplevel") { return (snapshot, "", 0) }
        if command.contains("git worktree remove") { return remove }
        if command.contains("printf '\\035'") { return (checkAll, "", 0) }
        if command.contains("git status --porcelain &&") { return (check, "", 0) }
        return ("", "unexpected command", 1)
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    func count(_ fragment: String) -> Int { commands.filter { $0.contains(fragment) }.count }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("condition never became true")
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class GitWorktreeRemovalTests: XCTestCase {
    private static let rs = "\u{1e}"
    private static let listing = """
    worktree /home/alice/dev/dash
    HEAD 1a2b3c4d
    branch refs/heads/main

    worktree /home/alice/dev/dash-current
    HEAD 2b3c4d5e
    branch refs/heads/current

    worktree /home/alice/dev/dash-old
    HEAD 3c4d5e6f
    branch refs/heads/old

    """

    private static let snapshot = "/home/alice/dev/dash-current\n# branch.head current\n"
        + rs + listing + rs + "1a2b3c4\u{1f}Add the git tab\u{1f}alice\u{1f}2 hours ago\u{1f}\n"

    private static func checkOutput(status: String, unmerged: String) -> String {
        [status, "", "", unmerged, listing].joined(separator: rs)
    }

    private static let removed = ["0", "", "gone", "0", "Deleted branch old"].joined(separator: "\u{1f}") + "\u{1d}"

    private let target = CommandTarget.remote(alias: "acme-devmachine", session: "dash")

    private func makeStore(
        check: String = checkOutput(status: " M a.swift\n", unmerged: "2\n"),
        checkAll: String = checkOutput(status: "", unmerged: "0\n") + "\u{1d}",
        remove: ScriptedGitRunner.Reply = (removed, "", 0)
    ) -> (GitStore, ScriptedGitRunner) {
        let runner = ScriptedGitRunner(snapshot: Self.snapshot, checkAll: checkAll, check: check, remove: remove)
        return (GitStore(host: HostRunner(remote: RemoteService(runner: runner)), demo: false), runner)
    }

    private func worktree(_ path: String) throws -> GitSnapshot.Worktree {
        try XCTUnwrap(XCTUnwrap(storeSnapshot).worktrees.first { $0.path == path })
    }

    private var storeSnapshot: GitSnapshot?

    private func started(_ store: GitStore) async throws {
        store.start(target)
        try await waitUntil { store.snapshot != nil }
        storeSnapshot = store.snapshot
    }

    func testTheMainAndTheCurrentWorktreeAreNeverChecked() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }
        try await started(store)

        store.requestRemoval(try worktree("/home/alice/dev/dash"))
        store.requestRemoval(try worktree("/home/alice/dev/dash-current"))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(store.removal)
        XCTAssertFalse(runner.commands.contains { $0.hasPrefix("cd '/home/alice/dev/dash' && git status") })
        XCTAssertFalse(runner.commands.contains { $0.hasPrefix("cd '/home/alice/dev/dash-current' && git status") })
    }

    func testRequestingRunsTheReadOnlyCheckInThatWorktree() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }
        try await started(store)

        store.requestRemoval(try worktree("/home/alice/dev/dash-old"))
        XCTAssertEqual(store.removal?.phase, .checking)
        try await waitUntil { store.removal?.phase == .ready }

        let check = try XCTUnwrap(store.removal?.check)
        XCTAssertEqual(check.branch, "old")
        XCTAssertEqual(check.uncommittedChanges, 1)
        XCTAssertEqual(check.unmergedCommits, 2)
        XCTAssertEqual(check.mainBranch, "main")
        XCTAssertTrue(runner.commands.contains { $0.hasPrefix("cd '/home/alice/dev/dash-old' && git status") })
    }

    func testADirtyWorktreeIsNotRemovedWithoutTheCheckbox() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }
        try await started(store)
        store.requestRemoval(try worktree("/home/alice/dev/dash-old"))
        try await waitUntil { store.removal?.phase == .ready }

        store.confirmRemoval(options: .init())
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(runner.count("git worktree remove"), 0)
        XCTAssertEqual(store.removal?.phase, .ready)
    }

    func testConfirmingRemovesFromTheMainCheckoutAndReadsTheListAgain() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }
        try await started(store)
        store.requestRemoval(try worktree("/home/alice/dev/dash-old"))
        try await waitUntil { store.removal?.phase == .ready }
        let reads = runner.count("rev-parse --show-toplevel")

        store.confirmRemoval(options: .init(discardChanges: true))
        try await waitUntil { store.removal == nil }
        try await waitUntil { runner.count("rev-parse --show-toplevel") > reads }

        let remove = try XCTUnwrap(runner.commands.first { $0.contains("git worktree remove") })
        XCTAssertTrue(remove.hasPrefix("cd '/home/alice/dev/dash' || exit 1; "))
        XCTAssertTrue(remove.contains("git worktree remove --force -- '/home/alice/dev/dash-old'"))
        XCTAssertFalse(remove.contains("git branch"))
    }

    func testAFailedRemoveShowsTheExactGitError() async throws {
        let stderr = "fatal: '/home/alice/dev/dash-old' contains modified or untracked files, use --force to delete it\n"
        let (store, _) = makeStore(remove: ("", stderr, 128))
        defer { store.stop() }
        try await started(store)
        store.requestRemoval(try worktree("/home/alice/dev/dash-old"))
        try await waitUntil { store.removal?.phase == .ready }

        store.confirmRemoval(options: .init(discardChanges: true))
        try await waitUntil { store.removal?.error != nil }

        let error = try XCTUnwrap(store.removal?.error)
        XCTAssertEqual(error.details, stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(error.title, "Could not remove the worktree")
    }

    func testCleanMergedWorktreesAreOfferedTogether() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }
        try await started(store)
        try await waitUntil { !store.mergedWorktrees.isEmpty }

        XCTAssertEqual(store.mergedWorktrees.map(\.path), ["/home/alice/dev/dash-old"])
        let checkAll = try XCTUnwrap(runner.commands.first { $0.contains("\\035") })
        XCTAssertFalse(checkAll.contains("cd '/home/alice/dev/dash' &&"))
        XCTAssertFalse(checkAll.contains("dash-current"))

        store.requestMergedRemoval()
        store.confirmMergedRemoval(deleteBranches: true)
        try await waitUntil { store.mergedRemoval == nil }
        XCTAssertEqual(runner.count("git worktree remove"), 1)
        let remove = try XCTUnwrap(runner.commands.first { $0.contains("git worktree remove") })
        XCTAssertTrue(remove.contains("git worktree remove -- '/home/alice/dev/dash-old'"))
        XCTAssertTrue(remove.contains("git branch -d -- 'old'"))
        XCTAssertFalse(remove.contains("--force"))
    }

    func testDemoModeShowsInventedWorktreesAndRunsNothing() async throws {
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: DemoMode.runner)), demo: true)
        defer { store.stop() }
        store.start(target)

        let snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertGreaterThan(snapshot.worktrees.count, 2)
        XCTAssertFalse(store.mergedWorktrees.isEmpty)
        let removable = try XCTUnwrap(snapshot.worktrees.first {
            WorktreeRemoval.block($0, currentRoot: snapshot.root) == nil
        })
        store.requestRemoval(removable)
        XCTAssertEqual(store.removal?.phase, .ready)
        store.confirmRemoval(options: .init(discardChanges: true, removeLocked: true))
        XCTAssertNil(store.removal)
    }
}
