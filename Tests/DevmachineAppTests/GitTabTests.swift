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
        XCTAssertEqual(ContextTab.allCases.map(\.title), ["Context", "Files", "Git"])
        XCTAssertEqual(ContextTab(rawValue: "git"), .git)
    }
}
