import XCTest
@testable import DevmachineCore

final class GitSnapshotParserTests: XCTestCase {
    private let rs = "\u{1e}"
    private let fs = "\u{1f}"

    private func output(status: String, worktrees: String = "", log: String = "") -> String {
        status + rs + worktrees + rs + log
    }

    private func logLine(
        sha: String,
        subject: String,
        author: String = "alice",
        age: String = "2 hours ago",
        refs: String = ""
    ) -> String {
        [sha, subject, author, age, refs].joined(separator: fs)
    }

    func testCleanRepoHasNoDirtyFilesAndNoDivergence() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(output(
            status: """
            /Users/alice/dev/dash
            # branch.oid 1a2b3c4d5e6f7a8b
            # branch.head main
            # branch.upstream origin/main
            # branch.ab +0 -0
            """,
            worktrees: """
            worktree /Users/alice/dev/dash
            HEAD 1a2b3c4d5e6f7a8b
            branch refs/heads/main
            """,
            log: logLine(sha: "1a2b3c4", subject: "Add the git tab")
        )))

        XCTAssertEqual(snapshot.root, "/Users/alice/dev/dash")
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertEqual(snapshot.upstream, "origin/main")
        XCTAssertEqual(snapshot.ahead, 0)
        XCTAssertEqual(snapshot.behind, 0)
        XCTAssertEqual(snapshot.dirtyFiles, 0)
        XCTAssertFalse(snapshot.isDirty)
        XCTAssertNil(snapshot.detachedHead)
        XCTAssertEqual(snapshot.commits.count, 1)
    }

    func testDirtyRepoCountsChangedFilesAndReadsAheadBehind() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(output(
            status: """
            /Users/alice/dev/dash
            # branch.oid 1a2b3c4d5e6f7a8b
            # branch.head da-git-tab
            # branch.upstream origin/da-git-tab
            # branch.ab +3 -2
            1 .M N... 100644 100644 100644 aaa bbb Sources/App.swift
            1 M. N... 100644 100644 100644 ccc ddd Sources/Theme.swift
            2 R. N... 100644 100644 100644 eee fff R100 new.swift\told.swift
            u UU N... 100644 100644 100644 100644 ggg hhh iii merged.swift
            ? Untracked.swift
            """,
            log: logLine(sha: "1a2b3c4", subject: "Work in progress")
        )))

        XCTAssertEqual(snapshot.branch, "da-git-tab")
        XCTAssertEqual(snapshot.ahead, 3)
        XCTAssertEqual(snapshot.behind, 2)
        XCTAssertEqual(snapshot.dirtyFiles, 5)
        XCTAssertTrue(snapshot.isDirty)
    }

    func testDetachedHeadHasNoBranchAndKeepsTheObjectId() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(output(
            status: """
            /Users/alice/dev/dash
            # branch.oid 9f8e7d6c5b4a3928
            # branch.head (detached)
            """
        )))

        XCTAssertNil(snapshot.branch)
        XCTAssertEqual(snapshot.detachedHead, "9f8e7d6c5b4a3928")
        XCTAssertNil(snapshot.upstream)
        XCTAssertEqual(snapshot.ahead, 0)
        XCTAssertEqual(snapshot.behind, 0)
    }

    func testTwoWorktreesMarkOnlyTheFirstAsMain() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(output(
            status: """
            /Users/alice/dev/dash
            # branch.head main
            """,
            worktrees: """
            worktree /Users/alice/dev/dash
            HEAD 1a2b3c4d5e6f7a8b
            branch refs/heads/main

            worktree /Users/alice/dev/dash-wt
            HEAD 9f8e7d6c5b4a3928
            branch refs/heads/da-git-tab
            """
        )))

        XCTAssertEqual(snapshot.worktrees.count, 2)
        XCTAssertEqual(snapshot.worktrees[0].path, "/Users/alice/dev/dash")
        XCTAssertEqual(snapshot.worktrees[0].branch, "main")
        XCTAssertEqual(snapshot.worktrees[0].head, "1a2b3c4d5e6f7a8b")
        XCTAssertTrue(snapshot.worktrees[0].isMain)
        XCTAssertEqual(snapshot.worktrees[1].path, "/Users/alice/dev/dash-wt")
        XCTAssertEqual(snapshot.worktrees[1].branch, "da-git-tab")
        XCTAssertFalse(snapshot.worktrees[1].isMain)
    }

    func testDetachedWorktreeHasNoBranch() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(output(
            status: "/Users/alice/dev/dash",
            worktrees: """
            worktree /Users/alice/dev/dash
            HEAD 1a2b3c4d5e6f7a8b
            detached
            """
        )))

        XCTAssertEqual(snapshot.worktrees.count, 1)
        XCTAssertNil(snapshot.worktrees[0].branch)
    }

    func testRefsDropTheHeadArrowAndKeepTagsAndRemotes() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(output(
            status: "/Users/alice/dev/dash",
            log: [
                logLine(sha: "1a2b3c4", subject: "Release", refs: "HEAD -> main, origin/main, tag: v1"),
                logLine(sha: "9f8e7d6", subject: "Earlier work, with a comma", age: "3 days ago")
            ].joined(separator: "\n")
        )))

        XCTAssertEqual(snapshot.commits.count, 2)
        XCTAssertEqual(snapshot.commits[0].refs, ["main", "origin/main", "tag: v1"])
        XCTAssertEqual(snapshot.commits[0].sha, "1a2b3c4")
        XCTAssertEqual(snapshot.commits[0].author, "alice")
        XCTAssertEqual(snapshot.commits[0].age, "2 hours ago")
        XCTAssertEqual(snapshot.commits[1].subject, "Earlier work, with a comma")
        XCTAssertEqual(snapshot.commits[1].age, "3 days ago")
        XCTAssertTrue(snapshot.commits[1].refs.isEmpty)
    }

    func testPrimaryRefPrefersATagThenALocalBranch() {
        func commit(_ refs: [String]) -> GitSnapshot.Commit {
            GitSnapshot.Commit(sha: "1a2b3c4", subject: "s", author: "alice", age: "now", refs: refs)
        }

        XCTAssertEqual(commit(["main", "origin/main", "tag: v1"]).primaryRef, "tag: v1")
        XCTAssertEqual(commit(["origin/main", "main"]).primaryRef, "main")
        XCTAssertEqual(commit(["origin/main"]).primaryRef, "origin/main")
        XCTAssertNil(commit([]).primaryRef)
    }

    func testEmptyLogGivesNoCommits() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse(output(
            status: """
            /Users/alice/dev/dash
            # branch.head main
            """,
            worktrees: """
            worktree /Users/alice/dev/dash
            HEAD 1a2b3c4d5e6f7a8b
            branch refs/heads/main
            """,
            log: ""
        )))

        XCTAssertTrue(snapshot.commits.isEmpty)
        XCTAssertEqual(snapshot.worktrees.count, 1)
    }

    func testOutputWithoutARepositoryRootIsNil() {
        XCTAssertNil(GitSnapshotParser.parse(""))
        XCTAssertNil(GitSnapshotParser.parse("fatal: not a git repository"))
    }

    func testMissingWorktreeAndLogSectionsStillParse() throws {
        let snapshot = try XCTUnwrap(GitSnapshotParser.parse("""
        /Users/alice/dev/dash
        # branch.head main
        """))

        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertTrue(snapshot.worktrees.isEmpty)
        XCTAssertTrue(snapshot.commits.isEmpty)
    }

    func testGitSnapshotCommandEscapesTheSessionAndSplitsOnRecordSeparators() {
        let command = RemoteCommands.gitSnapshot(session: "x'y")

        XCTAssertTrue(command.contains("tmux display -p -t 'x'\\''y' '#{pane_current_path}'"))
        XCTAssertTrue(command.contains("git rev-parse --show-toplevel"))
        XCTAssertTrue(command.contains("git status --porcelain=v2 --branch"))
        XCTAssertTrue(command.contains("git worktree list --porcelain"))
        XCTAssertTrue(command.contains("git log --format='%h%x1f%s%x1f%an%x1f%ar%x1f%D' -n 80"))
        XCTAssertEqual(command.components(separatedBy: "printf '\\x1e'").count - 1, 2)
    }
}
