import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class OwnershipGitRunner: CommandRunner, @unchecked Sendable {
    typealias Reply = (stdout: String, stderr: String, exitCode: Int32)

    private let lock = NSLock()
    private var sent: [String] = []
    var snapshot: String
    var check: String
    var remove: Reply = ("", "", 0)
    var leftover: String = ""

    init(snapshot: String, check: String) {
        self.snapshot = snapshot
        self.check = check
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws -> Reply {
        let command = args.last ?? ""
        lock.lock()
        sent.append(command)
        let snapshot = self.snapshot, check = self.check, remove = self.remove, leftover = self.leftover
        lock.unlock()
        if command.contains("rev-parse --show-toplevel") { return (snapshot, "", 0) }
        if command.contains("git worktree remove") { return remove }
        if command.contains("printf '\\035'") { return ("", "", 0) }
        if command.contains("echo present || echo gone") { return (leftover, "", 0) }
        if command.contains("git status --porcelain &&") { return (check, "", 0) }
        if command.contains("git worktree prune") { return ("", "", 0) }
        return ("", "unexpected command", 1)
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }
}

private final class FakeWorktreeAdmin: WorktreeAdmin, @unchecked Sendable {
    private let lock = NSLock()
    let machine: WorktreeAdminRemoval.Machine?
    var reply: (stdout: String, stderr: String, exitCode: Int32) = ("removed", "", 0)
    private(set) var lookups: [String] = []
    private(set) var runs: [(machine: String, script: String)] = []

    init(machine: WorktreeAdminRemoval.Machine?) {
        self.machine = machine
    }

    func machine(forWorkspace workspace: String) -> WorktreeAdminRemoval.Machine? {
        lock.lock()
        defer { lock.unlock() }
        lookups.append(workspace)
        return machine
    }

    func run(machine: String, script: String) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        defer { lock.unlock() }
        runs.append((machine, script))
        return reply
    }
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
final class GitWorktreeOwnershipTests: XCTestCase {
    private static let rs = "\u{1e}"
    private static let old = "/home/alice/dev/dash/.worktrees/old"
    private static let listing = """
    worktree /home/alice/dev/dash
    HEAD 1a2b3c4d
    branch refs/heads/main

    worktree /home/alice/dev/dash/.worktrees/current
    HEAD 2b3c4d5e
    branch refs/heads/current

    worktree /home/alice/dev/dash/.worktrees/old
    HEAD 3c4d5e6f
    branch refs/heads/old

    worktree /home/alice/dev/dash/.worktrees/gone
    HEAD 3c4d5e6f
    branch refs/heads/gone
    prunable gitdir file points to non-existent location

    """

    private static func snapshot(leftovers: [String] = []) -> String {
        "/home/alice/dev/dash/.worktrees/current\n# branch.head current\n"
            + rs + listing + rs + "1a2b3c4\u{1f}Add the git tab\u{1f}alice\u{1f}2 hours ago\u{1f}\n"
            + rs + leftovers.map { $0 + "\n" }.joined()
    }

    private static func check(foreign: [String]) -> String {
        ["", "", "", "0\n", listing, "alice\n" + foreign.map { $0 + "\n" }.joined() + "\(foreign.count)\n"]
            .joined(separator: rs)
    }

    private static let rootOwned = [old + "/build", old + "/build/cache"]

    private func makeStore(
        target: CommandTarget = .remote(alias: "acme-devmachine", session: "dash"),
        foreign: [String] = rootOwned,
        leftovers: [String] = [],
        machine: WorktreeAdminRemoval.Machine? = .init(name: "main", isSelf: false)
    ) -> (GitStore, OwnershipGitRunner, FakeWorktreeAdmin) {
        let runner = OwnershipGitRunner(
            snapshot: Self.snapshot(leftovers: leftovers), check: Self.check(foreign: foreign))
        let admin = FakeWorktreeAdmin(machine: machine)
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: runner)), admin: admin, demo: false)
        return (store, runner, admin)
    }

    private func started(_ store: GitStore, workspace: String? = "acme") async throws -> GitSnapshot {
        store.start(.remote(alias: "acme-devmachine", session: "dash"), workspace: workspace)
        try await waitUntil { store.snapshot != nil }
        return try XCTUnwrap(store.snapshot)
    }

    private func requestOld(_ store: GitStore, _ snapshot: GitSnapshot) async throws {
        store.requestRemoval(try XCTUnwrap(snapshot.worktrees.first { $0.path == Self.old }))
        try await waitUntil { store.removal?.phase == .ready && store.removal?.route != nil }
    }

    func testTheCheckShowsForeignFilesAndOffersTheMachineAdmin() async throws {
        let (store, _, admin) = makeStore()
        defer { store.stop() }
        try await requestOld(store, try await started(store))

        let check = try XCTUnwrap(store.removal?.check)
        XCTAssertEqual(check.foreignFiles?.paths, Self.rootOwned)
        XCTAssertEqual(check.foreignFiles?.count, 2)
        XCTAssertEqual(store.removal?.route, .admin(machine: "main"))
        XCTAssertEqual(admin.lookups, ["acme"])
        XCTAssertEqual(
            WorktreeRemovalText.foreignWarning(try XCTUnwrap(check.foreignFiles)),
            "2 files here belong to another user (e.g. root) — git can't delete them")
    }

    func testAMachineThatIsThisComputerGetsTheCommandsInstead() async throws {
        let (store, _, admin) = makeStore(machine: .init(name: "laptop", isSelf: true))
        defer { store.stop() }
        try await requestOld(store, try await started(store))

        XCTAssertEqual(store.removal?.route, .manual(.selfMachine))
        store.confirmAdminRemoval(options: .init(removeAsAdmin: true))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(admin.runs.isEmpty)
    }

    func testWithoutTheCLIThereIsNoAdminRoute() async throws {
        let (store, _, _) = makeStore(machine: nil)
        defer { store.stop() }
        try await requestOld(store, try await started(store))
        XCTAssertEqual(store.removal?.route, .manual(.noCLI))
    }

    func testTheAdminDoesNothingWithoutTheSecondCheckbox() async throws {
        let (store, runner, admin) = makeStore()
        defer { store.stop() }
        try await requestOld(store, try await started(store))

        store.confirmAdminRemoval(options: .init())
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(admin.runs.isEmpty)
        XCTAssertFalse(runner.commands.contains { $0.contains("git worktree prune") })
        XCTAssertEqual(store.removal?.phase, .ready)
    }

    func testTheAdminDeletesThenTheUserPrunesAndDeletesTheBranch() async throws {
        let (store, runner, admin) = makeStore()
        defer { store.stop() }
        try await requestOld(store, try await started(store))

        store.confirmAdminRemoval(options: .init(deleteBranch: true, removeAsAdmin: true))
        try await waitUntil { store.removal == nil }

        XCTAssertEqual(admin.runs.count, 1)
        XCTAssertEqual(admin.runs.first?.machine, "main")
        XCTAssertEqual(
            admin.runs.first?.script,
            WorktreeAdminRemoval.script(path: Self.old, mainWorktree: "/home/alice/dev/dash", user: "alice"))
        XCTAssertTrue(runner.commands.contains(
            "cd '/home/alice/dev/dash' && git worktree prune && git branch -d -- 'old'"))
        XCTAssertFalse(runner.commands.contains { $0.contains("git worktree remove") })
    }

    func testARefusedAdminScriptIsShownAndNothingIsPruned() async throws {
        let (store, runner, admin) = makeStore()
        admin.reply = ("", "refused: /home/alice/dev/dash/.worktrees/old is a mount point\n", 3)
        defer { store.stop() }
        try await requestOld(store, try await started(store))

        store.confirmAdminRemoval(options: .init(removeAsAdmin: true))
        try await waitUntil { store.removal?.error != nil }

        let error = try XCTUnwrap(store.removal?.error)
        XCTAssertEqual(error.title, "The machine admin did not remove it")
        XCTAssertTrue(error.details.contains("mount point"))
        XCTAssertFalse(runner.commands.contains { $0.contains("git worktree prune") })
    }

    func testAPermissionErrorFromGitReadsAsFilesNotAsARefusedLogin() async throws {
        let (store, runner, _) = makeStore()
        runner.remove = ("", "error: failed to delete '\(Self.old)': Permission denied\n", 255)
        runner.leftover = "present\n" + Self.rs + "worktree /home/alice/dev/dash\n" + Self.rs
            + "alice\n\(Self.old)/build\n1\n"
        defer { store.stop() }
        try await requestOld(store, try await started(store))

        store.confirmRemoval(options: .init())
        try await waitUntil { store.removal?.error != nil && store.removal?.leftover != nil }

        let error = try XCTUnwrap(store.removal?.error)
        XCTAssertEqual(error.title, "Could not remove the worktree")
        XCTAssertEqual(
            error.cause, "Some files in this worktree can't be deleted by alice: \(Self.old)/build")
        XCTAssertFalse(error.cause?.contains("SSH") ?? true)
        let leftover = try XCTUnwrap(store.removal?.leftover)
        XCTAssertTrue(leftover.exists)
        XCTAssertFalse(leftover.isRegistered)
        XCTAssertEqual(leftover.foreignFiles?.count, 1)
    }

    func testAnSSHRefusalStillReadsAsARefusedLogin() async throws {
        let (store, runner, _) = makeStore()
        runner.remove = ("", "alice@acme-devmachine: Permission denied (publickey).\n", 255)
        defer { store.stop() }
        try await requestOld(store, try await started(store))

        store.confirmRemoval(options: .init())
        try await waitUntil { store.removal?.error != nil }

        XCTAssertEqual(store.removal?.error?.cause, "The machine refused the SSH login.")
        XCTAssertNil(store.removal?.leftover)
        XCTAssertFalse(runner.commands.contains { $0.contains("echo present || echo gone") })
    }

    func testAPrunableWorktreeIsPrunedWithoutACheck() async throws {
        let (store, runner, _) = makeStore()
        defer { store.stop() }
        let snapshot = try await started(store)
        let gone = try XCTUnwrap(snapshot.worktrees.first { $0.isPrunable })

        store.requestRemoval(gone)
        XCTAssertEqual(store.removal?.kind, .prunable)
        XCTAssertEqual(store.removal?.phase, .ready)
        XCTAssertFalse(runner.commands.contains { $0.contains("cd '/home/alice/dev/dash/.worktrees/gone' && git status") })

        store.prune()
        try await waitUntil { store.removal == nil }
        XCTAssertTrue(runner.commands.contains("cd '/home/alice/dev/dash' && git worktree prune"))
    }

    func testALeftoverFolderIsListedAndCheckedBeforeAnythingIsDeleted() async throws {
        let leftoverPath = "/home/alice/dev/dash/.worktrees/half"
        let (store, runner, admin) = makeStore(leftovers: [leftoverPath])
        runner.leftover = "present\n" + Self.rs + "worktree /home/alice/dev/dash\n" + Self.rs
            + "alice\n\(leftoverPath)/node_modules\n7\n"
        defer { store.stop() }
        let snapshot = try await started(store)
        XCTAssertEqual(snapshot.leftovers, [leftoverPath])

        store.requestLeftoverRemoval(leftoverPath)
        XCTAssertEqual(store.removal?.kind, .leftover)
        try await waitUntil { store.removal?.phase == .ready && store.removal?.route != nil }
        XCTAssertEqual(store.removal?.leftover?.foreignFiles?.count, 7)
        XCTAssertEqual(store.removal?.route, .admin(machine: "main"))

        store.confirmAdminRemoval(options: .init(removeAsAdmin: true))
        try await waitUntil { store.removal == nil }
        XCTAssertEqual(
            admin.runs.first?.script,
            WorktreeAdminRemoval.script(path: leftoverPath, mainWorktree: "/home/alice/dev/dash", user: "alice"))
        XCTAssertTrue(runner.commands.contains("cd '/home/alice/dev/dash' && git worktree prune"))
    }

    func testALeftoverTheUserOwnsIsDeletedAsTheUser() async throws {
        let leftoverPath = "/home/alice/dev/dash/.worktrees/half"
        let (store, runner, admin) = makeStore(leftovers: [leftoverPath])
        runner.leftover = "present\n" + Self.rs + "worktree /home/alice/dev/dash\n" + Self.rs + "alice\n0\n"
        defer { store.stop() }
        _ = try await started(store)

        store.requestLeftoverRemoval(leftoverPath)
        try await waitUntil { store.removal?.phase == .ready }
        store.deleteLeftover()
        try await waitUntil { store.removal == nil }

        XCTAssertTrue(admin.runs.isEmpty)
        let delete = try XCTUnwrap(
            WorktreeRemoval.deleteLeftoverCommand(path: leftoverPath, mainWorktree: "/home/alice/dev/dash"))
        XCTAssertTrue(runner.commands.contains(delete))
    }
}
