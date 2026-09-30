import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

private final class SilentRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

@MainActor
final class GitTabTests: XCTestCase {
    private func store(snapshot: GitSnapshot?) -> GitStore {
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: SilentRunner())))
        store.snapshot = snapshot
        return store
    }

    private var fixture: GitSnapshot {
        GitSnapshot(
            root: "/home/alice/dev/dash",
            branch: "da-git-tab",
            upstream: "origin/da-git-tab",
            ahead: 2,
            behind: 1,
            dirtyFiles: 3,
            worktrees: [
                GitSnapshot.Worktree(
                    path: "/home/alice/dev/dash",
                    head: "1a2b3c4d",
                    branch: "main",
                    isMain: true
                ),
                GitSnapshot.Worktree(
                    path: "/home/alice/dev/dash-wt",
                    head: "9f8e7d6c",
                    branch: "da-git-tab",
                    isMain: false
                )
            ],
            commits: [
                GitSnapshot.Commit(
                    sha: "1a2b3c4",
                    subject: "Add the git tab",
                    author: "alice",
                    age: "2 hours ago",
                    refs: ["da-git-tab", "origin/da-git-tab", "tag: v1"]
                ),
                GitSnapshot.Commit(
                    sha: "9f8e7d6",
                    subject: "Extract the tab strip",
                    author: "alice",
                    age: "3 days ago",
                    refs: []
                )
            ]
        )
    }

    private func render(_ store: GitStore) throws -> NSImage {
        let view = GitTab(store: store, target: .remote(alias: "acme-devmachine", session: "dash"))
            .environmentObject(AppModel(store: SessionStore(runner: SilentRunner())))
            .frame(width: 300, height: 420)
        return try XCTUnwrap(ImageRenderer(content: view).nsImage)
    }

    func testTheTabRendersASnapshotAndTheEmptyState() throws {
        let withHistory = try render(store(snapshot: fixture))
        let withoutRepository = try render(store(snapshot: nil))

        XCTAssertEqual(withHistory.size.width, 300)
        XCTAssertEqual(withHistory.size.height, 420)
        XCTAssertEqual(withoutRepository.size.width, 300)
    }

    func testTheContextTabStripKeepsTheHeaderHeight() throws {
        let model = AppModel(store: SessionStore(runner: SilentRunner()))
        let suiteName = "dev.devmachine.app.gittab.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let panel = ContextPanel(store: ContextStore(services: fixtureServices()))
            .environmentObject(model)
            .environmentObject(SkillsStore())
            .environmentObject(SettingsStore(defaults: defaults))
            .frame(width: 300, height: 400)
        let image = try XCTUnwrap(ImageRenderer(content: panel).nsImage)

        XCTAssertEqual(image.size.width, 300)
        XCTAssertEqual(image.size.height, 400)
    }

    func testEveryTabHasATitle() {
        XCTAssertEqual(ContextTab.allCases.map(\.title), ["Context", "Preview", "Files", "Git"])
        XCTAssertEqual(ContextTab(rawValue: "git"), .git)
    }

    func testTheWarningsNameWhatWouldBeLost() throws {
        let check = try XCTUnwrap(DemoData.worktreeChecks.first { $0.path.hasSuffix("api-webhooks") })
        XCTAssertEqual(WorktreeRemovalText.warnings(check, deletingBranch: false).map(\.text), [
            "3 uncommitted changes will be lost",
            "1 commit not pushed to origin/webhooks-retry",
            "4 commits not merged into main",
            "Branch webhooks-retry will be kept",
        ])
        let locked = try XCTUnwrap(DemoData.worktreeChecks.first { $0.isLocked })
        XCTAssertTrue(WorktreeRemovalText.warnings(locked, deletingBranch: false).map(\.text)
            .contains("Locked: on an external disk"))
        let merged = try XCTUnwrap(DemoData.worktreeChecks.first { $0.isCleanAndMerged })
        XCTAssertEqual(WorktreeRemovalText.warnings(merged, deletingBranch: true), [])
        XCTAssertEqual(WorktreeRemovalText.removeMergedTitle(1), "Remove 1 merged…")
        XCTAssertEqual(WorktreeRemovalText.removeMergedTitle(3), "Remove 3 merged…")
    }

    func testTheOwnershipSectionRendersForEveryRoute() throws {
        let check = DemoData.foreignWorktreeCheck
        let worktree = GitSnapshot.Worktree(path: check.path, head: "4d5e6f7a", branch: check.branch, isMain: false)
        let routes: [WorktreeAdminRemoval.Route?] = [
            nil, .admin(machine: "main"), .manual(.thisMac), .manual(.selfMachine), .manual(.noCLI),
        ]
        for route in routes {
            var request = WorktreeRemovalRequest(worktree: worktree, check: check, phase: .ready)
            request.route = route
            request.mainWorktree = "/home/acme/dev/api"
            let sheet = WorktreeRemovalSheet(
                request: request,
                onRemove: { _ in }, onRemoveAsAdmin: { _ in }, onPrune: {}, onDeleteLeftover: {}, onCancel: {})
            XCTAssertEqual(try XCTUnwrap(ImageRenderer(content: sheet).nsImage, "\(String(describing: route))").size.width, 460)
        }
    }

    func testTheSheetOffersOnlyTheActionThatFits() {
        let worktree = GitSnapshot.Worktree(path: "/home/acme/dev/api/.worktrees/x", head: "", branch: nil, isMain: false)
        var request = WorktreeRemovalRequest(worktree: worktree, check: nil, phase: .ready)
        XCTAssertEqual(WorktreeRemovalText.primaryAction(request), .remove)
        request.kind = .prunable
        XCTAssertEqual(WorktreeRemovalText.primaryAction(request), .prune)
        request.kind = .leftover
        request.leftover = WorktreeLeftover(
            path: worktree.path, exists: true, isRegistered: false,
            foreignFiles: ForeignFiles(user: "acme", paths: [], count: 0))
        XCTAssertEqual(WorktreeRemovalText.primaryAction(request), .deleteFolder)
        request.leftover = WorktreeLeftover(
            path: worktree.path, exists: true, isRegistered: false,
            foreignFiles: ForeignFiles(user: "acme", paths: [worktree.path + "/db"], count: 1))
        XCTAssertNil(WorktreeRemovalText.primaryAction(request))
        request.leftover = WorktreeLeftover(path: worktree.path, exists: false, isRegistered: true, foreignFiles: nil)
        XCTAssertEqual(WorktreeRemovalText.primaryAction(request), .prune)
        request.kind = .worktree
        request.leftover = nil
        request.phase = .failed(DMErrorState(title: "Could not remove the worktree", message: "x"))
        XCTAssertNil(WorktreeRemovalText.primaryAction(request))
    }

    func testThePermissionWordsNameTheAccountAndThePath() {
        XCTAssertEqual(
            WorktreeRemovalText.deniedPath("error: failed to delete '/home/acme/dev/api/.worktrees/x': Permission denied\n"),
            "/home/acme/dev/api/.worktrees/x")
        XCTAssertNil(WorktreeRemovalText.deniedPath("fatal: not a working tree"))
        XCTAssertEqual(
            WorktreeRemovalText.permissionCause(user: nil, path: nil),
            "Some files in this worktree can't be deleted by this account.")
        XCTAssertEqual(
            WorktreeRemovalText.foreignWarning(ForeignFiles(user: "acme", paths: [], count: 1)),
            "1 file here belongs to another user (e.g. root) — git can't delete them")
        XCTAssertEqual(WorktreeRemovalText.moreForeign(ForeignFiles(user: "acme", paths: ["/a"], count: 3)), "and 2 more")
        XCTAssertNil(WorktreeRemovalText.moreForeign(ForeignFiles(user: "acme", paths: ["/a"], count: 1)))
    }

    func testTheRemovalSheetsRenderEveryPhase() throws {
        let worktree = try XCTUnwrap(DemoData.gitSnapshot.worktrees.first { $0.path.hasSuffix("api-webhooks") })
        let check = DemoData.worktreeChecks.first { $0.path == worktree.path }
        let phases: [WorktreeRemovalRequest.Phase] = [
            .checking, .ready, .removing,
            .failed(DMErrorState(title: "Could not remove the worktree", message: "fatal: not a working tree")),
            .removedKeepingBranch(DMErrorState(
                title: "Worktree removed, branch feature kept", cause: "Not merged into origin/feature",
                details: "error: the branch 'feature' is not fully merged")),
        ]
        for phase in phases {
            let sheet = WorktreeRemovalSheet(
                request: WorktreeRemovalRequest(worktree: worktree, check: check, phase: phase),
                onRemove: { _ in }, onRemoveAsAdmin: { _ in }, onPrune: {}, onDeleteLeftover: {}, onCancel: {})
            let image = try XCTUnwrap(ImageRenderer(content: sheet).nsImage, "\(phase)")
            XCTAssertEqual(image.size.width, 460)
        }
        let merged = MergedWorktreesRemovalSheet(
            request: MergedRemovalRequest(checks: DemoData.worktreeChecks.filter(\.isCleanAndMerged)),
            onRemove: { _ in }, onCancel: {})
        XCTAssertEqual(try XCTUnwrap(ImageRenderer(content: merged).nsImage).size.width, 420)
    }

    func testTheMergedSheetAfterARunShowsEachWorktreeAndOffersOnlyWhatIsLeft() throws {
        let checks = DemoData.worktreeChecks.filter(\.isCleanAndMerged)
        let results = [
            WorktreeRemovalResult(path: "/home/alice/dev/dash-a", branch: "a", outcome: .removed, branchOutcome: .deleted),
            WorktreeRemovalResult(
                path: "/home/alice/dev/dash-b", branch: "b", outcome: .removed,
                branchOutcome: .kept(reason: "not merged into origin/b", details: "error: not fully merged")),
            WorktreeRemovalResult(path: "/home/alice/dev/dash-c", branch: nil, outcome: .alreadyGone, branchOutcome: .notRequested),
            WorktreeRemovalResult(
                path: "/home/alice/dev/dash-d", branch: nil,
                outcome: .failed(details: "fatal: '/home/alice/dev/dash-d' contains modified or untracked files"),
                branchOutcome: .notRequested),
        ]
        var request = MergedRemovalRequest(checks: Array(checks.prefix(1)))
        XCTAssertEqual(WorktreeRemovalText.mergedTitle(request), "Remove 1 merged worktree?")
        request.results = results
        XCTAssertEqual(WorktreeRemovalText.mergedTitle(request), "3 removed, 1 failed, 1 branch kept: not merged into origin/b")
        XCTAssertEqual(results.map { WorktreeRemovalText.status($0).text }, [
            "Removed, branch deleted", "Removed, branch kept: not merged into origin/b", "Already gone", "Not removed",
        ])
        let sheet = MergedWorktreesRemovalSheet(request: request, onRemove: { _ in }, onCancel: {})
        XCTAssertEqual(try XCTUnwrap(ImageRenderer(content: sheet).nsImage).size.width, 420)
    }

    func testAWorktreeRemovedWithItsBranchKeptOffersNothingMore() throws {
        let worktree = try XCTUnwrap(DemoData.gitSnapshot.worktrees.first { $0.path.hasSuffix("api-webhooks") })
        let request = WorktreeRemovalRequest(
            worktree: worktree, check: DemoData.worktreeChecks.first { $0.path == worktree.path },
            phase: .removedKeepingBranch(DMErrorState(title: "Worktree removed, branch x kept", cause: nil, details: "")))
        XCTAssertNil(WorktreeRemovalText.primaryAction(request))
        XCTAssertNil(request.error)
    }

    func testTheDemoWorktreesRender() throws {
        let image = try render(store(snapshot: DemoData.gitSnapshot))
        XCTAssertEqual(image.size.width, 300)
    }
}
