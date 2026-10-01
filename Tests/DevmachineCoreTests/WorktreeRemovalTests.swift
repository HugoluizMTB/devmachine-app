import XCTest
@testable import DevmachineCore

final class WorktreeRemovalTests: XCTestCase {
    private let rs = "\u{1e}"
    private let gs = "\u{1d}"

    private func worktree(_ path: String, branch: String? = "feature", isMain: Bool = false) -> GitSnapshot.Worktree {
        GitSnapshot.Worktree(path: path, head: "1a2b3c4d", branch: branch, isMain: isMain)
    }

    private func check(
        path: String = "/home/alice/dev/dash-feature",
        branch: String? = "feature",
        uncommitted: Int = 0,
        unpushed: Int? = nil,
        unmerged: Int? = 0,
        lockReason: String? = nil,
        isLocked: Bool = false
    ) -> WorktreeCheck {
        WorktreeCheck(
            path: path, branch: branch, upstream: unpushed == nil ? nil : "origin/\(branch ?? "")",
            uncommittedChanges: uncommitted, unpushedCommits: unpushed, unmergedCommits: unmerged,
            mainBranch: "main", isLocked: isLocked || lockReason != nil, lockReason: lockReason)
    }

    // MARK: Gating

    func testTheMainAndTheCurrentWorktreeAreNotRemovable() {
        let root = "/home/alice/dev/dash-feature"
        XCTAssertEqual(
            WorktreeRemoval.block(worktree("/home/alice/dev/dash", branch: "main", isMain: true), currentRoot: root),
            .mainWorktree)
        XCTAssertEqual(WorktreeRemoval.block(worktree(root), currentRoot: root), .currentWorktree)
        XCTAssertNil(WorktreeRemoval.block(worktree("/home/alice/dev/dash-other"), currentRoot: root))
        XCTAssertFalse(WorktreeRemoval.Block.mainWorktree.reason.isEmpty)
        XCTAssertNotEqual(WorktreeRemoval.Block.mainWorktree.reason, WorktreeRemoval.Block.currentWorktree.reason)
    }

    func testACleanWorktreeNeedsNoCheckbox() {
        XCTAssertTrue(WorktreeRemoval.canRemove(check(), options: .init()))
        XCTAssertEqual(WorktreeRemoval.force(for: check(), options: .init()), .none)
    }

    func testADirtyWorktreeNeedsTheDiscardCheckbox() {
        let dirty = check(uncommitted: 3)
        XCTAssertFalse(WorktreeRemoval.canRemove(dirty, options: .init()))
        XCTAssertTrue(WorktreeRemoval.canRemove(dirty, options: .init(discardChanges: true)))
        XCTAssertEqual(WorktreeRemoval.force(for: dirty, options: .init(discardChanges: true)), .force)
    }

    func testALockedWorktreeNeedsTheLockCheckboxAndDoubleForce() {
        let locked = check(lockReason: "on a usb disk")
        XCTAssertFalse(WorktreeRemoval.canRemove(locked, options: .init()))
        XCTAssertTrue(WorktreeRemoval.canRemove(locked, options: .init(removeLocked: true)))
        XCTAssertEqual(WorktreeRemoval.force(for: locked, options: .init(removeLocked: true)), .forceTwice)

        let lockedAndDirty = check(uncommitted: 1, lockReason: nil, isLocked: true)
        XCTAssertFalse(WorktreeRemoval.canRemove(lockedAndDirty, options: .init(removeLocked: true)))
        XCTAssertTrue(WorktreeRemoval.canRemove(
            lockedAndDirty, options: .init(discardChanges: true, removeLocked: true)))
    }

    func testTheBranchIsOfferedForDeletionOnlyWhenMerged() {
        XCTAssertTrue(WorktreeRemoval.canDeleteBranch(check(unmerged: 0)))
        XCTAssertFalse(WorktreeRemoval.canDeleteBranch(check(unmerged: 2)))
        XCTAssertFalse(WorktreeRemoval.canDeleteBranch(check(unmerged: nil)))
        XCTAssertFalse(WorktreeRemoval.canDeleteBranch(check(branch: nil, unmerged: 0)))
        XCTAssertFalse(WorktreeRemoval.canDeleteBranch(check(branch: "main", unmerged: 0)))
    }

    func testOnlyCleanMergedUnlockedWorktreesCountAsMerged() {
        XCTAssertTrue(check().isCleanAndMerged)
        XCTAssertFalse(check(uncommitted: 1).isCleanAndMerged)
        XCTAssertFalse(check(unmerged: 1).isCleanAndMerged)
        XCTAssertFalse(check(unmerged: nil).isCleanAndMerged)
        XCTAssertFalse(check(isLocked: true).isCleanAndMerged)
    }

    // MARK: Commands

    private let main = "/home/alice/dev/dash"

    func testOneStepPerWorktreeWithItsForceAndBranch() {
        XCTAssertEqual(
            WorktreeRemoval.step(check(), options: .init()),
            .init(path: "/home/alice/dev/dash-feature", branch: nil, force: .none))
        XCTAssertEqual(
            WorktreeRemoval.step(check(uncommitted: 2), options: .init(discardChanges: true)),
            .init(path: "/home/alice/dev/dash-feature", branch: nil, force: .force))
        XCTAssertEqual(
            WorktreeRemoval.step(check(unmerged: 2), options: .init(deleteBranch: true))?.branch, nil)
        XCTAssertEqual(
            WorktreeRemoval.step(check(isLocked: true), options: .init(removeLocked: true, deleteBranch: true)),
            .init(path: "/home/alice/dev/dash-feature", branch: "feature", force: .forceTwice))
        XCTAssertNil(WorktreeRemoval.step(check(uncommitted: 1), options: .init()))
        XCTAssertNil(WorktreeRemoval.step(check(isLocked: true), options: .init()))
    }

    func testTheMergedSweepTakesOnlyCleanMergedWorktreesAndNeverForces() {
        let steps = WorktreeRemoval.mergedSteps(
            [check(path: "/home/alice/dev/dash-a", branch: "a"),
             check(path: "/home/alice/dev/dash-b", branch: "b", uncommitted: 1),
             check(path: "/home/alice/dev/dash-c", branch: "c")],
            deleteBranches: true)
        XCTAssertEqual(steps, [
            .init(path: "/home/alice/dev/dash-a", branch: "a", force: .none),
            .init(path: "/home/alice/dev/dash-c", branch: "c", force: .none),
        ])
        XCTAssertEqual(
            WorktreeRemoval.mergedSteps([check(path: "/home/alice/dev/dash-a", branch: "a")], deleteBranches: false)
                .map(\.branch),
            [nil])
        XCTAssertNil(WorktreeRemoval.removeCommand([], mainWorktree: main))
    }

    func testRemovalRunsFromTheMainCheckoutOneWorktreeAfterTheOtherThenPrunes() throws {
        let command = try XCTUnwrap(WorktreeRemoval.removeCommand(
            [.init(path: "/home/alice/dev/dash-a", branch: "a", force: .none),
             .init(path: "/home/alice/dev/dash-b", branch: nil, force: .force)],
            mainWorktree: main))
        XCTAssertTrue(command.hasPrefix("cd '/home/alice/dev/dash' || exit 1; "))
        XCTAssertTrue(command.hasSuffix("; git worktree prune"))
        let a = try XCTUnwrap(command.range(of: "git worktree remove -- '/home/alice/dev/dash-a'"))
        let branchA = try XCTUnwrap(command.range(of: "git branch -d -- 'a'"))
        let b = try XCTUnwrap(command.range(of: "git worktree remove --force -- '/home/alice/dev/dash-b'"))
        XCTAssertLessThan(a.lowerBound, branchA.lowerBound)
        XCTAssertLessThan(branchA.lowerBound, b.lowerBound)
        XCTAssertFalse(command.contains(" & "))
        XCTAssertFalse(command.contains("-D"))
        XCTAssertFalse(command.contains("&& git branch"))
    }

    func testPathsAndBranchesAreQuotedAgainstTheShell() throws {
        let hostile = "/home/alice/dev/it's a $(touch pwned) `x` \"q\""
        let step = try XCTUnwrap(WorktreeRemoval.step(
            check(path: hostile, branch: "da-it's"), options: .init(deleteBranch: true)))
        let command = try XCTUnwrap(WorktreeRemoval.removeCommand([step], mainWorktree: "/home/alice/dev/my $HOME"))
        XCTAssertTrue(command.hasPrefix("cd '/home/alice/dev/my $HOME' || exit 1; "))
        XCTAssertTrue(command.contains("-- '/home/alice/dev/it'\\''s a $(touch pwned) `x` \"q\"'"))
        XCTAssertTrue(command.contains("git branch -d -- 'da-it'\\''s'"))

        let checkCommand = WorktreeRemoval.checkCommand(path: hostile, mainBranch: "ma'in")
        XCTAssertTrue(checkCommand.hasPrefix("cd '/home/alice/dev/it'\\''s a $(touch pwned) `x` \"q\"' && "))
        XCTAssertTrue(checkCommand.contains("'refs/heads/ma'\\''in..HEAD'"))
    }

    // MARK: Results

    private let us = "\u{1f}"

    private func record(_ fields: String...) -> String { fields.joined(separator: us) + gs }

    func testEachWorktreeGetsItsOwnResult() {
        let steps: [WorktreeRemoval.RemovalStep] = [
            .init(path: "/home/alice/dev/dash-a", branch: "a", force: .none),
            .init(path: "/home/alice/dev/dash-b", branch: "b", force: .none),
            .init(path: "/home/alice/dev/dash-c", branch: nil, force: .none),
            .init(path: "/home/alice/dev/dash-d", branch: "d", force: .none),
        ]
        let refused = "warning: not deleting branch 'b' that is not yet merged to\n"
            + "         'refs/remotes/origin/b', even though it is merged to HEAD\n"
            + "error: the branch 'b' is not fully merged"
        let dirty = "fatal: '/home/alice/dev/dash-c' contains modified or untracked files, use --force to delete it"
        let output = record("0", "", "gone", "0", "Deleted branch a (was 1a2b3c4).")
            + record("0", "", "gone", "1", refused)
            + record("128", dirty, "present")
            + record("128", "fatal: '/home/alice/dev/dash-d' is not a working tree", "gone", "1", "error: branch 'd' not found")

        let results = WorktreeRemoval.parseRemoval(output, steps: steps, failure: "")
        XCTAssertEqual(results.map(\.path), steps.map(\.path))
        XCTAssertEqual(results[0].outcome, .removed)
        XCTAssertEqual(results[0].branchOutcome, .deleted)
        XCTAssertEqual(results[1].outcome, .removed)
        XCTAssertEqual(results[1].branchOutcome, .kept(reason: "not merged into origin/b", details: refused))
        XCTAssertEqual(results[2].outcome, .failed(details: dirty))
        XCTAssertEqual(results[2].branchOutcome, .notRequested)
        XCTAssertEqual(results[3].outcome, .alreadyGone)
        XCTAssertEqual(results[3].branchOutcome, .alreadyGone)
        XCTAssertEqual(results.map(\.isGone), [true, true, false, true])
    }

    func testABranchStillCheckedOutOrUnmergedIsKeptWithAPlainReason() {
        let steps: [WorktreeRemoval.RemovalStep] = [
            .init(path: "/home/alice/dev/dash-a", branch: "a", force: .none),
            .init(path: "/home/alice/dev/dash-b", branch: "b", force: .none),
        ]
        let output = record("0", "", "gone", "1", "error: cannot delete branch 'a' used by worktree at '/home/alice/dev/x'")
            + record("0", "", "gone", "1", "error: the branch 'b' is not fully merged\nhint: If you are sure")
        let results = WorktreeRemoval.parseRemoval(output, steps: steps, failure: "")
        XCTAssertEqual(results.map(\.keptBranchReason), ["checked out in another worktree", "not fully merged"])
    }

    func testAWorktreeTheOutputNeverReachedFailsWithTheCommandsError() {
        let steps: [WorktreeRemoval.RemovalStep] = [
            .init(path: "/home/alice/dev/dash-a", branch: nil, force: .none),
            .init(path: "/home/alice/dev/dash-b", branch: nil, force: .none),
        ]
        let results = WorktreeRemoval.parseRemoval(
            record("0", "", "gone"), steps: steps, failure: "ssh: connection closed")
        XCTAssertEqual(results.map(\.outcome), [.removed, .failed(details: "ssh: connection closed")])
    }

    func testTheSummaryCountsWhatWasRemovedAndWhyABranchWasKept() {
        func result(_ outcome: WorktreeRemovalResult.Outcome, _ branch: WorktreeRemovalResult.BranchOutcome)
            -> WorktreeRemovalResult {
            WorktreeRemovalResult(path: "/home/alice/dev/x", branch: "x", outcome: outcome, branchOutcome: branch)
        }
        XCTAssertEqual(
            WorktreeRemoval.summary([
                result(.removed, .deleted), result(.alreadyGone, .alreadyGone), result(.removed, .deleted),
                result(.removed, .kept(reason: "not merged into main", details: "")),
            ]),
            "4 removed, 1 branch kept: not merged into main")
        XCTAssertEqual(
            WorktreeRemoval.summary([
                result(.removed, .kept(reason: "not merged into origin/a", details: "")),
                result(.removed, .kept(reason: "not fully merged", details: "")),
                result(.failed(details: "fatal: x"), .notRequested),
            ]),
            "2 removed, 1 failed, 2 branches kept")
        XCTAssertEqual(WorktreeRemoval.summary([result(.removed, .notRequested)]), "1 removed")
    }

    // MARK: The check

    func testTheCheckCommandIsReadOnly() {
        let command = WorktreeRemoval.checkCommand(path: "/home/alice/dev/dash-feature", mainBranch: "main")
        for word in ["remove", "prune", "branch -d", "branch -D", "reset", "checkout", "clean"] {
            XCTAssertFalse(command.contains(word), word)
        }
        XCTAssertTrue(command.contains("git status --porcelain"))
        XCTAssertTrue(command.contains("git rev-list --count 'refs/heads/main..HEAD'"))
        XCTAssertTrue(command.contains("git worktree list --porcelain"))
    }

    func testTheCheckWithoutAMainBranchSkipsTheMergeCount() {
        let command = WorktreeRemoval.checkCommand(path: "/home/alice/dev/dash-feature", mainBranch: nil)
        XCTAssertFalse(command.contains("refs/heads/"))
    }

    private func checkOutput(
        status: String = "", upstream: String = "", unpushed: String = "", unmerged: String = "",
        worktrees: String
    ) -> String {
        [status, upstream, unpushed, unmerged, worktrees].joined(separator: rs)
    }

    private let listing = """
    worktree /home/alice/dev/dash
    HEAD 1a2b3c4d
    branch refs/heads/main

    worktree /home/alice/dev/dash-feature
    HEAD 9f8e7d6c
    branch refs/heads/feature
    locked on a usb disk

    worktree /home/alice/dev/dash-bare-lock
    HEAD 9f8e7d6c
    detached
    locked

    """

    func testParsesADirtyAheadLockedWorktree() throws {
        let parsed = try XCTUnwrap(WorktreeRemoval.parseCheck(
            checkOutput(
                status: " M Sources/App.swift\n?? notes.txt\nD  old.swift\n",
                upstream: "origin/feature\n", unpushed: "2\n", unmerged: "5\n", worktrees: listing),
            path: "/home/alice/dev/dash-feature", mainBranch: "main"))
        XCTAssertEqual(parsed.branch, "feature")
        XCTAssertEqual(parsed.upstream, "origin/feature")
        XCTAssertEqual(parsed.uncommittedChanges, 3)
        XCTAssertEqual(parsed.unpushedCommits, 2)
        XCTAssertEqual(parsed.unmergedCommits, 5)
        XCTAssertTrue(parsed.isLocked)
        XCTAssertEqual(parsed.lockReason, "on a usb disk")
        XCTAssertTrue(parsed.isDirty)
    }

    func testParsesACleanMergedWorktreeWithoutUpstream() throws {
        let parsed = try XCTUnwrap(WorktreeRemoval.parseCheck(
            checkOutput(unmerged: "0\n", worktrees: listing.replacingOccurrences(of: "locked on a usb disk\n", with: "")),
            path: "/home/alice/dev/dash-feature", mainBranch: "main"))
        XCTAssertNil(parsed.upstream)
        XCTAssertNil(parsed.unpushedCommits)
        XCTAssertEqual(parsed.unmergedCommits, 0)
        XCTAssertFalse(parsed.isLocked)
        XCTAssertTrue(parsed.isCleanAndMerged)
    }

    func testALockWithoutAReasonIsStillALock() throws {
        let parsed = try XCTUnwrap(WorktreeRemoval.parseCheck(
            checkOutput(worktrees: listing), path: "/home/alice/dev/dash-bare-lock", mainBranch: nil))
        XCTAssertTrue(parsed.isLocked)
        XCTAssertNil(parsed.lockReason)
        XCTAssertNil(parsed.branch)
        XCTAssertNil(parsed.unmergedCommits)
    }

    func testATruncatedOutputIsNotACheck() {
        XCTAssertNil(WorktreeRemoval.parseCheck("", path: "/home/alice/dev/dash-feature", mainBranch: "main"))
        XCTAssertNil(WorktreeRemoval.parseCheck(
            " M a.swift\n" + rs + "origin/feature", path: "/home/alice/dev/dash-feature", mainBranch: "main"))
    }

    func testCheckAllReadsEveryWorktreeInOneRoundTrip() throws {
        let paths = ["/home/alice/dev/dash-feature", "/home/alice/dev/gone"]
        let command = WorktreeRemoval.checkAllCommand(paths: paths, mainBranch: "main")
        XCTAssertTrue(command.contains("( cd '/home/alice/dev/dash-feature' && "))
        XCTAssertTrue(command.contains("( cd '/home/alice/dev/gone' && "))

        let output = checkOutput(unmerged: "0\n", worktrees: listing) + gs + "sh: cd: no such directory\n" + gs
        let checks = WorktreeRemoval.parseCheckAll(output, paths: paths, mainBranch: "main")
        XCTAssertEqual(checks.map(\.path), ["/home/alice/dev/dash-feature"])
    }

    func testTheSnapshotListingReadsLocks() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(
            "/home/alice/dev/dash\n# branch.head main\n" + rs + listing + rs))
        XCTAssertEqual(snapshot.worktrees.map(\.isLocked), [false, true, true])
        XCTAssertEqual(snapshot.worktrees[1].lockReason, "on a usb disk")
        XCTAssertNil(snapshot.worktrees[2].lockReason)
    }
}
