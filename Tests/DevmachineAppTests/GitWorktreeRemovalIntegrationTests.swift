import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Runs the real remove flow with the real `git`, on repositories made in a
/// temporary folder for this test only.
@MainActor
final class GitWorktreeRemovalIntegrationTests: XCTestCase {
    private var base = ""
    private var repo = ""

    override func setUp() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-worktrees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        base = try XCTUnwrap(realpath(temp.path, nil).map { String(cString: $0) })
        repo = base + "/dash"
        try git(["init", "-q", "-b", "main", repo], in: base)
        try git(["commit", "-q", "--allow-empty", "-m", "init"], in: repo)
    }

    override func tearDown() async throws {
        if base.contains("/dm-worktrees-") {
            _ = try? shell("chmod -R u+w '\(base)'")
            try? FileManager.default.removeItem(atPath: base)
        }
    }

    @discardableResult
    private func git(_ args: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = [
            "PATH": "/usr/bin:/bin", "HOME": base, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "alice", "GIT_AUTHOR_EMAIL": "alice@example.com",
            "GIT_COMMITTER_NAME": "alice", "GIT_COMMITTER_EMAIL": "alice@example.com",
        ]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " "))")
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @discardableResult
    private func shell(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func branches() throws -> [String] {
        try git(["branch", "--format=%(refname:short)"], in: repo).split(separator: "\n").map(String.init)
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition never became true")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func remove(
        _ path: String, in store: GitStore, options: WorktreeRemoval.Options,
        expect: (WorktreeCheck) -> Void = { _ in }
    ) async throws {
        let worktree = try XCTUnwrap(store.snapshot?.worktrees.first { $0.path == path }, path)
        store.requestRemoval(worktree)
        try await waitUntil { store.removal?.phase == .ready }
        expect(try XCTUnwrap(store.removal?.check))
        store.confirmRemoval(options: options)
        try await waitUntil { store.removal == nil || store.removal?.error != nil }
        XCTAssertNil(store.removal?.error?.details)
        try await waitUntil { store.snapshot?.worktrees.contains { $0.path == path } == false }
    }

    func testTheWholeRemoveFlowAgainstRealGit() async throws {
        let merged = base + "/dash-merged"
        let dirty = base + "/dash it's $HOME `x`"
        let locked = base + "/dash-locked"
        try git(["worktree", "add", "-q", "-b", "merged", merged], in: repo)
        try git(["worktree", "add", "-q", "-b", "feature", dirty], in: repo)
        try git(["commit", "-q", "--allow-empty", "-m", "work"], in: dirty)
        try "draft".write(toFile: dirty + "/notes.txt", atomically: true, encoding: .utf8)
        try git(["worktree", "add", "-q", "-b", "stuck", locked], in: repo)
        try git(["worktree", "lock", "--reason", "on a usb disk", locked], in: repo)

        let store = GitStore(host: HostRunner(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.snapshot?.worktrees.count == 4 }
        try await waitUntil { !store.mergedWorktrees.isEmpty }
        XCTAssertEqual(store.mergedWorktrees.map(\.path), [merged])

        let main = try XCTUnwrap(store.snapshot?.worktrees.first)
        store.requestRemoval(main)
        XCTAssertNil(store.removal)

        let dirtyRow = try XCTUnwrap(store.snapshot?.worktrees.first { $0.path == dirty })
        store.requestRemoval(dirtyRow)
        try await waitUntil { store.removal?.phase == .ready }
        store.confirmRemoval(options: .init())
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirty))
        store.cancelRemoval()

        try await remove(dirty, in: store, options: .init(discardChanges: true, deleteBranch: true)) { check in
            XCTAssertEqual(check.uncommittedChanges, 1)
            XCTAssertEqual(check.unmergedCommits, 1)
            XCTAssertFalse(WorktreeRemoval.canDeleteBranch(check))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirty))
        XCTAssertTrue(try branches().contains("feature"))

        try await remove(merged, in: store, options: .init(deleteBranch: true)) { check in
            XCTAssertTrue(check.isCleanAndMerged)
        }
        XCTAssertFalse(try branches().contains("merged"))

        try await remove(locked, in: store, options: .init(removeLocked: true)) { check in
            XCTAssertTrue(check.isLocked)
            XCTAssertEqual(check.lockReason, "on a usb disk")
        }
        XCTAssertTrue(try branches().contains("stuck"))
        XCTAssertEqual(try git(["worktree", "list", "--porcelain"], in: repo)
            .split(separator: "\n").filter { $0.hasPrefix("worktree ") }.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base + "/x"))
    }

    func testRemovingEveryMergedWorktreeAtOnce() async throws {
        try git(["worktree", "add", "-q", "-b", "one", base + "/dash-one"], in: repo)
        try git(["worktree", "add", "-q", "-b", "two", base + "/dash two"], in: repo)
        try git(["worktree", "add", "-q", "-b", "wip", base + "/dash-wip"], in: repo)
        try git(["commit", "-q", "--allow-empty", "-m", "wip"], in: base + "/dash-wip")

        let store = GitStore(host: HostRunner(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.mergedWorktrees.count == 2 }

        store.requestMergedRemoval()
        store.confirmMergedRemoval(deleteBranches: true)
        try await waitUntil { store.mergedRemoval == nil }
        try await waitUntil { store.snapshot?.worktrees.count == 2 }

        XCTAssertEqual(try branches().sorted(), ["main", "wip"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: base + "/dash-wip"))
        try await waitUntil { store.mergedWorktrees.isEmpty }
    }

    /// The branch `three` has an upstream that is behind it, so `git branch
    /// -d` refuses it even though it is merged into main. Every folder is
    /// still removed.
    private func makeThreeMergedWorktreesOneWithAStaleUpstream() throws -> [String] {
        let origin = base + "/origin.git"
        try git(["init", "-q", "--bare", origin], in: base)
        try git(["remote", "add", "origin", origin], in: repo)
        try git(["push", "-q", "-u", "origin", "main"], in: repo)
        let paths = [base + "/dash-one", base + "/dash two", base + "/dash-three"]
        try git(["worktree", "add", "-q", "-b", "one", paths[0]], in: repo)
        try git(["worktree", "add", "-q", "-b", "two", paths[1]], in: repo)
        try git(["worktree", "add", "-q", "-b", "three", paths[2]], in: repo)
        try git(["commit", "-q", "--allow-empty", "-m", "pushed"], in: paths[2])
        try git(["push", "-q", "-u", "origin", "three"], in: paths[2])
        try git(["commit", "-q", "--allow-empty", "-m", "not pushed"], in: paths[2])
        try git(["merge", "-q", "--ff-only", "three"], in: repo)
        return paths
    }

    func testABranchGitRefusesDoesNotTurnABulkRemovalIntoAFailure() async throws {
        let paths = try makeThreeMergedWorktreesOneWithAStaleUpstream()
        let store = GitStore(host: HostRunner(), admin: RefusingAdmin(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.mergedWorktrees.count == 3 }

        store.requestMergedRemoval()
        store.confirmMergedRemoval(deleteBranches: true)
        try await waitUntil { store.mergedRemoval?.results != nil }
        try await waitUntil { store.snapshot?.worktrees.count == 1 }

        let request = try XCTUnwrap(store.mergedRemoval)
        XCTAssertEqual(request.summary, "3 removed, 1 branch kept: not merged into origin/three")
        let results = try XCTUnwrap(request.results)
        XCTAssertEqual(Set(results.map(\.path)), Set(paths))
        XCTAssertTrue(results.allSatisfy(\.isGone))
        XCTAssertEqual(results.first { $0.path == paths[2] }?.keptBranchReason, "not merged into origin/three")
        XCTAssertTrue(request.checks.isEmpty)
        for path in paths { XCTAssertFalse(FileManager.default.fileExists(atPath: path), path) }
        XCTAssertEqual(try branches().sorted(), ["main", "three"])
        try await waitUntil { store.mergedWorktrees.isEmpty }

        store.confirmMergedRemoval(deleteBranches: true)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.mergedRemoval?.results, results)
        XCTAssertEqual(store.mergedRemoval?.isRemoving, false)
    }

    func testWorktreesRemovedElsewhereAfterTheCheckCountAsRemoved() async throws {
        let paths = [base + "/dash-one", base + "/dash-two", base + "/dash-three"]
        for (path, branch) in zip(paths, ["one", "two", "three"]) {
            try git(["worktree", "add", "-q", "-b", branch, path], in: repo)
        }
        let store = GitStore(host: HostRunner(), admin: RefusingAdmin(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.mergedWorktrees.count == 3 }

        store.requestMergedRemoval()
        try git(["worktree", "remove", paths[0]], in: repo)
        try FileManager.default.removeItem(atPath: paths[1])
        store.confirmMergedRemoval(deleteBranches: false)
        try await waitUntil { store.mergedRemoval == nil }
        try await waitUntil { store.snapshot?.worktrees.count == 1 }

        XCTAssertEqual(try branches().sorted(), ["main", "one", "three", "two"])
        XCTAssertEqual(try git(["worktree", "list", "--porcelain"], in: repo)
            .split(separator: "\n").filter { $0.hasPrefix("worktree ") }.count, 1)
    }

    func testAWorktreeGitRefusesFailsAloneWithItsOwnErrorAndIsTheOnlyOneOfferedAgain() async throws {
        let kept = base + "/dash-busy"
        try git(["worktree", "add", "-q", "-b", "one", base + "/dash-one"], in: repo)
        try git(["worktree", "add", "-q", "-b", "busy", kept], in: repo)
        try git(["worktree", "add", "-q", "-b", "two", base + "/dash-two"], in: repo)
        let store = GitStore(host: HostRunner(), admin: RefusingAdmin(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.mergedWorktrees.count == 3 }

        store.requestMergedRemoval()
        try "draft".write(toFile: kept + "/notes.txt", atomically: true, encoding: .utf8)
        store.confirmMergedRemoval(deleteBranches: true)
        try await waitUntil { store.mergedRemoval?.results != nil }

        let request = try XCTUnwrap(store.mergedRemoval)
        XCTAssertEqual(request.summary, "2 removed, 1 failed")
        let failed = try XCTUnwrap(request.results?.first { $0.path == kept })
        guard case let .failed(details) = failed.outcome else { return XCTFail("\(failed.outcome)") }
        XCTAssertTrue(details.contains("contains modified or untracked files"), details)
        XCTAssertEqual(failed.branchOutcome, .notRequested)
        XCTAssertEqual(request.checks.map(\.path), [kept])
        XCTAssertEqual(try branches().sorted(), ["busy", "main"])

        try FileManager.default.removeItem(atPath: kept + "/notes.txt")
        store.confirmMergedRemoval(deleteBranches: true)
        try await waitUntil { store.mergedRemoval == nil }
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept))
        XCTAssertEqual(try branches(), ["main"])
    }

    func testASingleRemoveWhoseBranchGitRefusesSaysTheWorktreeIsGoneAndTheBranchKept() async throws {
        let paths = try makeThreeMergedWorktreesOneWithAStaleUpstream()
        let store = GitStore(host: HostRunner(), admin: RefusingAdmin(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.snapshot?.worktrees.count == 4 }

        store.requestRemoval(try XCTUnwrap(store.snapshot?.worktrees.first { $0.path == paths[2] }))
        try await waitUntil { store.removal?.phase == .ready }
        store.confirmRemoval(options: .init(deleteBranch: true))
        try await waitUntil { store.removal?.phase != .removing }

        guard case let .removedKeepingBranch(state) = store.removal?.phase else {
            return XCTFail("\(String(describing: store.removal?.phase))")
        }
        XCTAssertEqual(state.title, "Worktree removed, branch three kept")
        XCTAssertEqual(state.cause, "Not merged into origin/three")
        XCTAssertTrue(state.details.contains("not fully merged"), state.details)
        XCTAssertNil(store.removal?.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths[2]))
        XCTAssertTrue(try branches().contains("three"))
    }

    func testASingleRemoveOfAFolderAlreadyGoneIsDone() async throws {
        let gone = base + "/dash-gone"
        try git(["worktree", "add", "-q", "-b", "gone", gone], in: repo)
        let store = GitStore(host: HostRunner(), admin: RefusingAdmin(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.snapshot?.worktrees.count == 2 }

        store.requestRemoval(try XCTUnwrap(store.snapshot?.worktrees.first { $0.path == gone }))
        try await waitUntil { store.removal?.phase == .ready }
        try git(["worktree", "remove", gone], in: repo)
        store.confirmRemoval(options: .init(deleteBranch: true))
        try await waitUntil { store.removal == nil }
        XCTAssertEqual(try branches(), ["main"])
        try await waitUntil { store.snapshot?.worktrees.count == 1 }
    }

    func testAFileGitCannotDeleteLeavesALeftoverTheNextCheckFindsAndRemoves() async throws {
        let stuck = repo + "/.worktrees/stuck"
        try git(["worktree", "add", "-q", "-b", "stuck", stuck], in: repo)
        XCTAssertEqual(try shell("mkdir -p '\(stuck)/build/cache' && touch '\(stuck)/build/cache/db' && chmod 555 '\(stuck)/build/cache'"), 0)

        let admin = RefusingAdmin()
        let store = GitStore(host: HostRunner(), admin: admin, demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.snapshot?.worktrees.count == 2 }

        store.requestRemoval(try XCTUnwrap(store.snapshot?.worktrees.first { $0.path == stuck }))
        try await waitUntil { store.removal?.phase == .ready && store.removal?.route != nil }
        let check = try XCTUnwrap(store.removal?.check)
        XCTAssertEqual(check.foreignFiles, ForeignFiles(user: NSUserName(), paths: [], count: 0))
        XCTAssertEqual(store.removal?.route, .manual(.thisMac))

        XCTAssertTrue(check.isDirty)
        store.confirmRemoval(options: .init(discardChanges: true))
        try await waitUntil { store.removal?.error != nil && store.removal?.leftover != nil }
        let error = try XCTUnwrap(store.removal?.error)
        XCTAssertTrue(error.details.contains("Permission denied"), error.details)
        XCTAssertEqual(error.cause, "Some files in this worktree can't be deleted by \(NSUserName()): \(stuck)")
        let leftover = try XCTUnwrap(store.removal?.leftover)
        XCTAssertTrue(leftover.exists)
        XCTAssertFalse(leftover.isRegistered)
        XCTAssertEqual(leftover.foreignFiles?.count, 0)
        XCTAssertEqual(WorktreeRemovalText.primaryAction(try XCTUnwrap(store.removal)), .deleteFolder)
        store.cancelRemoval()

        try await waitUntil { store.snapshot?.leftovers == [stuck] }
        XCTAssertEqual(store.snapshot?.worktrees.count, 1)
        store.requestLeftoverRemoval(stuck)
        try await waitUntil { store.removal?.phase == .ready }
        store.deleteLeftover()
        try await waitUntil { store.removal == nil }
        try await waitUntil { store.snapshot?.leftovers.isEmpty == true }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stuck))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/.git"))
        XCTAssertTrue(admin.wasCalled == false)
    }

    func testAFolderWithoutItsGitFileCountsAsALeftoverOnlyInsideDotWorktrees() async throws {
        let half = repo + "/.worktrees/half"
        let sibling = base + "/dash-feature"
        try git(["worktree", "add", "-q", "-b", "half", half], in: repo)
        try git(["worktree", "add", "-q", "-b", "feature", sibling], in: repo)
        XCTAssertEqual(try shell("rm -f '\(half)/.git' && rm -rf '\(repo)/.git/worktrees/half'"), 0)
        XCTAssertEqual(try shell("mkdir -p '\(base)/unrelated/src'"), 0)

        let store = GitStore(host: HostRunner(), admin: RefusingAdmin(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.snapshot != nil }
        XCTAssertEqual(store.snapshot?.worktrees.count, 2)
        XCTAssertEqual(store.snapshot?.leftovers, [half])
    }

    func testAWorktreeWhoseFolderIsGoneIsPruned() async throws {
        let gone = base + "/dash-gone"
        try git(["worktree", "add", "-q", "-b", "gone", gone], in: repo)
        try FileManager.default.removeItem(atPath: gone)

        let store = GitStore(host: HostRunner(), admin: RefusingAdmin(), demo: false)
        defer { store.stop() }
        store.start(.local(session: "dash", path: repo))
        try await waitUntil { store.snapshot?.worktrees.count == 2 }
        let row = try XCTUnwrap(store.snapshot?.worktrees.first { $0.path == gone })
        XCTAssertTrue(row.isPrunable)

        store.requestRemoval(row)
        XCTAssertEqual(store.removal?.kind, .prunable)
        store.prune()
        try await waitUntil { store.removal == nil }
        try await waitUntil { store.snapshot?.worktrees.count == 1 }
        XCTAssertTrue(try branches().contains("gone"))
    }
}

private final class RefusingAdmin: WorktreeAdmin, @unchecked Sendable {
    private(set) var wasCalled = false

    func machine(forWorkspace workspace: String) -> WorktreeAdminRemoval.Machine? {
        wasCalled = true
        return nil
    }

    func run(machine: String, script: String) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        wasCalled = true
        return ("", "never on this Mac", 1)
    }
}
