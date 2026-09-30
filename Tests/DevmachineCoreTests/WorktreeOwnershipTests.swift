import XCTest
@testable import DevmachineCore

final class WorktreeOwnershipTests: XCTestCase {
    private let rs = "\u{1e}"
    private let path = "/home/alice/dev/dash/.worktrees/old"
    private let main = "/home/alice/dev/dash"

    private let listing = """
    worktree /home/alice/dev/dash
    HEAD 1a2b3c4d
    branch refs/heads/main

    worktree /home/alice/dev/dash/.worktrees/old
    HEAD 9f8e7d6c
    branch refs/heads/old

    """

    private func check(foreign: ForeignFiles? = nil, uncommitted: Int = 0, locked: Bool = false) -> WorktreeCheck {
        WorktreeCheck(
            path: path, branch: "old", upstream: nil, uncommittedChanges: uncommitted,
            unpushedCommits: nil, unmergedCommits: 0, mainBranch: "main",
            isLocked: locked, lockReason: nil, foreignFiles: foreign)
    }

    private let rootOwned = ForeignFiles(
        user: "alice", paths: ["/home/alice/dev/dash/.worktrees/old/build"], count: 1)

    // MARK: The ownership probe

    func testTheCheckListsFilesThatBelongToAnotherUserReadOnly() {
        let command = WorktreeRemoval.checkCommand(path: path, mainBranch: "main")
        XCTAssertTrue(command.contains("id -un"))
        XCTAssertTrue(command.contains("find '/home/alice/dev/dash/.worktrees/old' ! -user \"$u\" -print"))
        XCTAssertTrue(command.contains("NR<=10"))
        for word in ["remove", "prune", "rm ", "chmod", "chown", "sudo", "-delete", "-exec"] {
            XCTAssertFalse(command.contains(word), word)
        }
    }

    func testCheckingEveryWorktreeSkipsTheOwnershipWalk() {
        let command = WorktreeRemoval.checkAllCommand(paths: [path], mainBranch: "main")
        XCTAssertFalse(command.contains("find "))
    }

    func testTheProbeQuotesAPathThatLooksLikeShell() {
        let command = WorktreeRemoval.checkCommand(path: "/home/alice/it's $(x) `y`", mainBranch: nil)
        XCTAssertTrue(command.contains("find '/home/alice/it'\\''s $(x) `y`' ! -user"))
    }

    func testParsesForeignFilesWithTheirCount() throws {
        let probe = "alice\n\(path)/build\n\(path)/build/cache db\n42\n"
        let output = ["", "", "", "0\n", listing, probe].joined(separator: rs)
        let parsed = try XCTUnwrap(WorktreeRemoval.parseCheck(output, path: path, mainBranch: "main"))
        let foreign = try XCTUnwrap(parsed.foreignFiles)
        XCTAssertEqual(foreign.user, "alice")
        XCTAssertEqual(foreign.paths, ["\(path)/build", "\(path)/build/cache db"])
        XCTAssertEqual(foreign.count, 42)
        XCTAssertTrue(parsed.hasForeignFiles)
    }

    func testAWorktreeWhereEveryFileIsTheUsersHasNoForeignFiles() throws {
        let output = ["", "", "", "0\n", listing, "alice\n0\n"].joined(separator: rs)
        let parsed = try XCTUnwrap(WorktreeRemoval.parseCheck(output, path: path, mainBranch: "main"))
        XCTAssertEqual(parsed.foreignFiles, ForeignFiles(user: "alice", paths: [], count: 0))
        XCTAssertFalse(parsed.hasForeignFiles)
    }

    func testAnOlderCheckWithoutTheProbeStillParses() throws {
        let output = ["", "", "", "0\n", listing].joined(separator: rs)
        let parsed = try XCTUnwrap(WorktreeRemoval.parseCheck(output, path: path, mainBranch: "main"))
        XCTAssertNil(parsed.foreignFiles)
    }

    func testAProbeWithoutACountIsIgnored() {
        XCTAssertNil(WorktreeRemoval.parseForeignFiles("alice\n\(path)/build\n"))
        XCTAssertNil(WorktreeRemoval.parseForeignFiles(""))
    }

    // MARK: Prunable and left-over worktrees

    func testTheListingMarksAWorktreeWhoseFolderIsGoneAsPrunable() {
        let worktrees = GitSnapshotParser.parseWorktreeList(
            listing + "\nworktree /home/alice/dev/dash/.worktrees/gone\nHEAD 1a2b3c4d\nbranch refs/heads/gone\n"
                + "prunable gitdir file points to non-existent location\n")
        XCTAssertEqual(worktrees.map(\.isPrunable), [false, false, true])
    }

    func testThePruneCommandRunsFromTheMainCheckout() {
        XCTAssertEqual(WorktreeRemoval.pruneCommand(mainWorktree: main), "cd '/home/alice/dev/dash' && git worktree prune")
    }

    func testTheSnapshotListsFoldersGitNoLongerKnows() throws {
        let command = RemoteCommands.gitSnapshotBody
        XCTAssertTrue(command.contains("sh -c "))
        XCTAssertTrue(command.contains("/.worktrees"))
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(
            "/home/alice/dev/dash\n# branch.head main\n" + rs + listing + rs + "" + rs
                + "/home/alice/dev/dash/.worktrees/left over\n"))
        XCTAssertEqual(snapshot.leftovers, ["/home/alice/dev/dash/.worktrees/left over"])
    }

    func testAnOlderSnapshotHasNoLeftovers() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(
            "/home/alice/dev/dash\n# branch.head main\n" + rs + listing + rs))
        XCTAssertEqual(snapshot.leftovers, [])
    }

    func testTheLeftoverCheckReadsWhetherTheFolderIsStillThereAndWhoOwnsIt() throws {
        let command = WorktreeRemoval.leftoverCommand(path: path, mainWorktree: main)
        XCTAssertTrue(command.hasPrefix("cd '/home/alice/dev/dash' && "))
        for word in ["remove", "prune", "rm ", "chmod", "sudo"] {
            XCTAssertFalse(command.contains(word), word)
        }
        let present = try XCTUnwrap(WorktreeRemoval.parseLeftover(
            "present\n" + rs + "worktree /home/alice/dev/dash\n" + rs + "alice\n\(path)/build\n3\n", path: path))
        XCTAssertTrue(present.exists)
        XCTAssertFalse(present.isRegistered)
        XCTAssertEqual(present.foreignFiles?.count, 3)

        let gone = try XCTUnwrap(WorktreeRemoval.parseLeftover("gone\n" + rs + listing + rs, path: path))
        XCTAssertFalse(gone.exists)
        XCTAssertTrue(gone.isRegistered)
        XCTAssertNil(gone.foreignFiles)
        XCTAssertNil(WorktreeRemoval.parseLeftover("", path: path))
    }

    func testDeletingALeftoverAsTheUserMakesItWritableFirstAndNeverTouchesTheMainCheckout() {
        XCTAssertEqual(
            WorktreeRemoval.deleteLeftoverCommand(path: path, mainWorktree: main),
            "cd '/home/alice/dev/dash' && chmod -R u+w '/home/alice/dev/dash/.worktrees/old'"
                + " && rm -rf -- '/home/alice/dev/dash/.worktrees/old' && git worktree prune")
        XCTAssertNil(WorktreeRemoval.deleteLeftoverCommand(path: main, mainWorktree: main))
        XCTAssertNil(WorktreeRemoval.deleteLeftoverCommand(path: "/home/alice/dev", mainWorktree: main))
        XCTAssertNil(WorktreeRemoval.deleteLeftoverCommand(path: "relative/old", mainWorktree: main))
    }

    // MARK: Who may remove as the machine's admin

    private let remote = WorktreeAdminRemoval.Machine(name: "main", isSelf: false)

    func testAdminRemovalIsOfferedOnlyForARemoteMachineInsideTheUsersHome() {
        XCTAssertEqual(
            WorktreeAdminRemoval.route(isLocalSession: false, machine: remote, user: "alice", path: path, mainWorktree: main),
            .admin(machine: "main"))
        XCTAssertEqual(
            WorktreeAdminRemoval.route(isLocalSession: true, machine: remote, user: "alice", path: path, mainWorktree: main),
            .manual(.thisMac))
        XCTAssertEqual(
            WorktreeAdminRemoval.route(
                isLocalSession: false, machine: .init(name: "laptop", isSelf: true),
                user: "alice", path: path, mainWorktree: main),
            .manual(.selfMachine))
        XCTAssertEqual(
            WorktreeAdminRemoval.route(isLocalSession: false, machine: nil, user: "alice", path: path, mainWorktree: main),
            .manual(.noCLI))
        XCTAssertEqual(
            WorktreeAdminRemoval.route(
                isLocalSession: false, machine: remote, user: "alice", path: "/srv/dash/old", mainWorktree: main),
            .manual(.outsideHome))
        XCTAssertEqual(
            WorktreeAdminRemoval.route(
                isLocalSession: false, machine: remote, user: "bob", path: path, mainWorktree: main),
            .manual(.outsideHome))
    }

    func testTheHomeGuardRefusesEveryWayOut() {
        XCTAssertTrue(WorktreeAdminRemoval.isInsideHome(path, user: "alice"))
        for outside in [
            "/home/alice", "/home/alice/", "/home/alicex/dev", "/home/alice/../bob/dev", "/home/alice/./dev",
            "/home/alice/dev/..", "home/alice/dev", "/home//alice/dev", "/home/alice/dev\nx", "/",
        ] {
            XCTAssertFalse(WorktreeAdminRemoval.isInsideHome(outside, user: "alice"), outside)
        }
        for user in ["", "..", "a/b", "root user", "Alice", "-x", "a'b"] {
            XCTAssertFalse(WorktreeAdminRemoval.isInsideHome("/home/\(user)/dev/x", user: user), user)
        }
    }

    func testTheAdminScriptCarriesEveryValueAsBase64() throws {
        let odd = "/home/alice/dev/dash/.worktrees/it's $(rm -rf ~) `x`"
        let command = try XCTUnwrap(WorktreeAdminRemoval.script(path: odd, mainWorktree: main, user: "alice"))
        XCTAssertFalse(command.contains("rm -rf ~"))
        XCTAssertFalse(command.contains("it's"))
        XCTAssertTrue(command.contains(Data(odd.utf8).base64EncodedString()))
        XCTAssertTrue(command.contains(Data(main.utf8).base64EncodedString()))
        XCTAssertTrue(command.contains(Data("alice".utf8).base64EncodedString()))
        XCTAssertTrue(command.hasPrefix("sh -c '"))
    }

    func testTheAdminScriptVerifiesBeforeItDeletes() throws {
        let command = try XCTUnwrap(WorktreeAdminRemoval.script(path: path, mainWorktree: main, user: "alice"))
        for fragment in [
            "realpath -e", "mountpoint -q", "gitdir: ", "/.git/worktrees/", "$m/.worktrees", "--one-file-system", "sudo -n",
        ] {
            XCTAssertTrue(command.contains(fragment), fragment)
        }
        let verify = try XCTUnwrap(command.range(of: "mountpoint -q"))
        let delete = try XCTUnwrap(command.range(of: "rm -rf --one-file-system"))
        XCTAssertLessThan(verify.lowerBound, delete.lowerBound)
    }

    func testTheAdminScriptRefusesWhatTheGuardRefuses() {
        XCTAssertNil(WorktreeAdminRemoval.script(path: "/srv/dash/old", mainWorktree: main, user: "alice"))
        XCTAssertNil(WorktreeAdminRemoval.script(path: main, mainWorktree: main, user: "alice"))
        XCTAssertNil(WorktreeAdminRemoval.script(path: "/home/alice/dev", mainWorktree: main, user: "alice"))
        XCTAssertNil(WorktreeAdminRemoval.script(path: path, mainWorktree: "/srv/dash", user: "alice"))
        XCTAssertNil(WorktreeAdminRemoval.script(path: path, mainWorktree: main, user: "root user"))
    }

    func testAfterTheAdminTheUserPrunesAndOptionallyUnlocksAndDeletesTheBranch() {
        XCTAssertEqual(
            WorktreeAdminRemoval.afterAdminCommand(path: path, mainWorktree: main, unlock: false, branch: nil),
            "cd '/home/alice/dev/dash' && git worktree prune")
        XCTAssertEqual(
            WorktreeAdminRemoval.afterAdminCommand(path: path, mainWorktree: main, unlock: true, branch: "old"),
            "cd '/home/alice/dev/dash' && { git worktree unlock -- '/home/alice/dev/dash/.worktrees/old'"
                + " 2>/dev/null || true; } && git worktree prune && git branch -d -- 'old'")
    }

    func testAdminRemovalNeedsTheRouteTheSecondCheckboxAndTheUsualConsent() {
        let admin = WorktreeAdminRemoval.Route.admin(machine: "main")
        var options = WorktreeRemoval.Options()
        XCTAssertFalse(WorktreeAdminRemoval.canRemove(check(foreign: rootOwned), options: options, route: admin))
        options.removeAsAdmin = true
        XCTAssertTrue(WorktreeAdminRemoval.canRemove(check(foreign: rootOwned), options: options, route: admin))
        XCTAssertFalse(WorktreeAdminRemoval.canRemove(
            check(foreign: rootOwned), options: options, route: .manual(.selfMachine)))
        XCTAssertFalse(WorktreeAdminRemoval.canRemove(check(foreign: rootOwned, uncommitted: 2), options: options, route: admin))
        options.discardChanges = true
        XCTAssertTrue(WorktreeAdminRemoval.canRemove(check(foreign: rootOwned, uncommitted: 2), options: options, route: admin))
        XCTAssertFalse(WorktreeAdminRemoval.canRemove(check(foreign: rootOwned, locked: true), options: options, route: admin))
    }

    func testTheManualStepsNameBothAccounts() {
        let remoteSteps = WorktreeAdminRemoval.manualSteps(path: path, mainWorktree: main, isLocalSession: false)
        XCTAssertEqual(remoteSteps.asAdmin, "sudo rm -rf --one-file-system -- '/home/alice/dev/dash/.worktrees/old'")
        XCTAssertEqual(remoteSteps.asUser, "git -C '/home/alice/dev/dash' worktree prune")
        let localSteps = WorktreeAdminRemoval.manualSteps(path: path, mainWorktree: main, isLocalSession: true)
        XCTAssertEqual(localSteps.asAdmin, "sudo rm -rf -- '/home/alice/dev/dash/.worktrees/old'")
    }
}
