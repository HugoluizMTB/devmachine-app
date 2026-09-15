import XCTest
import Combine
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [String]
    private(set) var calls = 0

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return outputs.count > 1 ? outputs.removeFirst() : (outputs.first ?? "")
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

private final class CountingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var callsByAlias: [String: Int] = [:]

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        guard let alias = args.first else { return "" }
        lock.lock()
        callsByAlias[alias, default: 0] += 1
        lock.unlock()
        return "dash|1\n@@PANES@@\ndash|claude"
    }

    func calls(for alias: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callsByAlias[alias] ?? 0
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
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
final class AppModelTests: XCTestCase {
    func testRefreshAllCallsEachAliasOnce() async throws {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]

        model.refreshAll()

        try await waitUntil { runner.calls(for: "acme-devmachine") == 1 && runner.calls(for: "beta-devmachine") == 1 }

        XCTAssertEqual(runner.calls(for: "acme-devmachine"), 1)
        XCTAssertEqual(runner.calls(for: "beta-devmachine"), 1)
    }

    func testSelectingASessionPollsOnlyTheSelectedAlias() {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]
        model.sessionsByAlias = [
            "acme-devmachine": [TmuxSession(name: "dash", windows: 1, hasClaude: true)]
        ]

        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))

        XCTAssertTrue(model.hasSelectionPollTimer)
        XCTAssertEqual(model.selectionPollTarget, "acme-devmachine")
    }

    func testChangingSelectionRetargetsThePoll() {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]
        model.sessionsByAlias = [
            "acme-devmachine": [TmuxSession(name: "dash", windows: 1, hasClaude: true)],
            "beta-devmachine": [TmuxSession(name: "web", windows: 1, hasClaude: true)]
        ]

        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        XCTAssertEqual(model.selectionPollTarget, "acme-devmachine")

        model.clickSession(SessionRef(alias: "beta-devmachine", name: "web"))
        XCTAssertEqual(model.selectionPollTarget, "beta-devmachine")
    }

    func testSelectionStartsThePollAndHomeStopsIt() {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        model.sessionsByAlias = [
            "acme-devmachine": [TmuxSession(name: "dash", windows: 1, hasClaude: true)]
        ]

        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        XCTAssertTrue(model.hasSelectionPollTimer)
        XCTAssertEqual(model.selectionPollTarget, "acme-devmachine")

        model.goHome()

        XCTAssertFalse(model.hasSelectionPollTimer)
        XCTAssertNil(model.selectionPollTarget)
    }

    func testTheLastPaletteItemIsTheLocalOperatorSession() {
        let model = AppModel(store: SessionStore(runner: CountingRunner()))
        model.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "myhost",
            publicIP: "203.0.113.10",
            baseDomain: "example.com"
        )

        let last = model.paletteItems().last
        XCTAssertEqual(last?.title, "Operator")
        XCTAssertEqual(last?.subtitle, "Local")
        XCTAssertEqual(last?.target, .localSession(name: "Operator", path: "/Users/alice/dev/ops"))
    }

    func testPollWithSameResultDoesNotRepublish() async throws {
        let runner = ScriptedRunner(outputs: ["dash|1\n@@PANES@@\ndash|claude"])
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.sessionsByAlias["acme-devmachine"] != nil }

        let changes = ChangeCounter()
        let token = model.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { runner.callCount == 2 }
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(model.sessionsByAlias["acme-devmachine"]?.count, 1)
        XCTAssertEqual(changes.count, 0)
    }

    func testPollWithNewResultRepublishes() async throws {
        let runner = ScriptedRunner(outputs: [
            "dash|1\n@@PANES@@\ndash|claude",
            "dash|1\nweb|2\n@@PANES@@\ndash|claude"
        ])
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.sessionsByAlias["acme-devmachine"]?.count == 1 }

        let changes = ChangeCounter()
        let token = model.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.sessionsByAlias["acme-devmachine"]?.count == 2 }

        XCTAssertEqual(changes.count, 1)
    }

    func testRefreshSkipsTickWhileTheSameAliasIsInFlight() async throws {
        let runner = BlockingRunner(output: "dash|1\n@@PANES@@\ndash|claude")
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { runner.callCount == 1 }

        model.refresh(alias: "acme-devmachine")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.callCount, 1)

        runner.release()
        try await waitUntil { model.sessionsByAlias["acme-devmachine"] != nil }

        model.refresh(alias: "acme-devmachine")
        runner.release()
        try await waitUntil { runner.callCount == 2 }
    }

    func testRefreshOfAnotherAliasIsNotBlocked() async throws {
        let runner = BlockingRunner(output: "dash|1\n@@PANES@@\ndash|claude")
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]

        model.refresh(alias: "acme-devmachine")
        model.refresh(alias: "beta-devmachine")

        try await waitUntil { runner.callCount == 2 }
        runner.release()
        runner.release()
    }

    func testOfflineAliasStaysOfflineWithoutRepublishing() async throws {
        let runner = ThrowingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.offlineAliases.contains("acme-devmachine") }

        let changes = ChangeCounter()
        let token = model.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { runner.callCount == 2 }
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(changes.count, 0)
    }

    func testAnotherContextTabStopsTheContextPoll() {
        let model = AppModel(store: SessionStore(runner: CountingRunner()))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        model.sessionsByAlias = [
            "acme-devmachine": [TmuxSession(name: "dash", windows: 1, hasClaude: true)]
        ]
        model.contextTab = .context
        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        XCTAssertTrue(model.context.isPolling)

        model.contextTab = .git
        XCTAssertFalse(model.context.isPolling)

        model.contextTab = .context
        XCTAssertTrue(model.context.isPolling)
        model.context.stop()
    }

    func testOpeningASessionAsksForKeyboardFocus() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        let pending = TerminalRegistry.shared.pendingFocusKind
        XCTAssertEqual(pending, .remote(alias: "acme-devmachine", session: "dash"))
    }

    func testStackingAsksForFocusOnTheFirstCell() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.stackSessions([
            SessionRef(alias: "acme-devmachine", name: "dash"),
            SessionRef(alias: "acme-devmachine", name: "api")
        ])
        let pending = TerminalRegistry.shared.pendingFocusKind
        XCTAssertEqual(pending, .remote(alias: "acme-devmachine", session: "dash"))
    }

    func testOpeningALocalSessionClearsTheSessionHighlight() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        XCTAssertFalse(model.selectedSessions.isEmpty)

        model.selection = .localSession(name: Workspace.operatorSession, path: "/tmp")
        XCTAssertTrue(model.selectedSessions.isEmpty)
        XCTAssertNil(model.selectionAnchor)
    }

    func testGoingHomeClearsTheSessionHighlight() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        model.selection = nil
        XCTAssertTrue(model.selectedSessions.isEmpty)
    }
    @MainActor
    func testLocalIsAlwaysTheLastWorkspace() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine"),
        ]
        XCTAssertEqual(model.sidebarWorkspaces.map(\.name), ["acme", "beta", "Local"])
        XCTAssertTrue(model.sidebarWorkspaces.last?.isLocal == true)
    }

    @MainActor
    func testLocalWorkspaceIsNotPolledOverSSH() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        // `workspaces` is what the ssh sweep walks; Local is added for the
        // sidebar alone and must never reach it.
        XCTAssertFalse(model.workspaces.contains { $0.isLocal })
    }

    @MainActor
    func testLocalAlwaysOffersTheOperatorSession() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        XCTAssertEqual(model.localSessions.map(\.name), ["Operator"])
    }

    @MainActor
    func testAddingAFolderCreatesALocalSessionAndOpensIt() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.addLocalSession(path: "/Users/alice/dev/acme")

        XCTAssertEqual(model.localSessions.map(\.name), ["Operator", "acme"])
        XCTAssertEqual(
            model.selection, .localSession(name: "acme", path: "/Users/alice/dev/acme"))
        model.removeLocalSession(name: "acme")
    }

    @MainActor
    func testTheSameFolderTwiceBecomesTwoSessions() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.addLocalSession(path: "/Users/alice/dev/acme")
        model.addLocalSession(path: "/Users/alice/dev/acme")

        XCTAssertEqual(model.localSessions.map(\.name), ["Operator", "acme", "acme 2"])
        model.removeLocalSession(name: "acme")
        model.removeLocalSession(name: "acme 2")
    }

    @MainActor
    func testRemovingALocalSessionDropsItAndClearsTheSelection() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.addLocalSession(path: "/Users/alice/dev/acme")
        model.removeLocalSession(name: "acme")

        XCTAssertEqual(model.localSessions.map(\.name), ["Operator"])
        XCTAssertNil(model.selection)
    }

    @MainActor
    func testTheOperatorSessionCannotBeRemoved() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.removeLocalSession(name: Workspace.operatorSession)

        XCTAssertEqual(model.localSessions.map(\.name), ["Operator"])
    }

    @MainActor
    func testNothingConnectsBeforeASweepStarts() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        XCTAssertNil(model.connectingLabel)
        XCTAssertEqual(model.sweepTotal, 0)
    }

    @MainActor
    func testTheSweepCountsWorkspacesWhileItRuns() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine"),
            Workspace(name: "gamma", alias: "gamma-devmachine"),
        ]
        model.refreshAll()

        XCTAssertEqual(model.sweepTotal, 3)
        XCTAssertEqual(model.sweepDone, 0)
        XCTAssertEqual(model.connectingLabel, "Connecting 1 of 3 workspaces\u{2026}")
    }

    @MainActor
    func testTheLabelNeverCountsPastTheTotal() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        model.refreshAll()
        model.sweepDoneForTesting(1)

        XCTAssertEqual(model.connectingLabel, "Connecting 1 of 1 workspaces\u{2026}")
    }


    @MainActor
    func testATransferShowsABarAndThenClearsIt() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.beginTransfer(label: "Sending image\u{2026}", total: 1000)
        XCTAssertEqual(model.transfer?.done, 0)
        XCTAssertEqual(model.transfer?.total, 1000)

        model.advanceTransfer(done: 400)
        XCTAssertEqual(model.transfer?.done, 400)
        XCTAssertEqual(model.transfer?.label, "Sending image\u{2026}")

        model.endTransfer()
        XCTAssertNil(model.transfer)
    }

    @MainActor
    func testProgressWithoutATransferIsIgnored() {
        let model = AppModel(store: SessionStore(runner: BlockingRunner(output: "")))
        model.advanceTransfer(done: 10)
        XCTAssertNil(model.transfer)
    }


    @MainActor
    func testWakingLiftsThePauseAndSweepsAgain() {
        let model = AppModel(store: SessionStore(runner: UnreachableRunner()))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        model.refreshAll()

        // The sweep marked the workspace offline and paused polling; without a
        // wake the sidebar would stay red for up to two minutes.
        let waitForSweep = expectation(description: "sweep")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { waitForSweep.fulfill() }
        wait(for: [waitForSweep], timeout: 2)
        XCTAssertTrue(model.isPollingPaused)

        model.resumePollingAfterWake()
        XCTAssertFalse(model.isPollingPaused)
    }

}

private final class ThrowingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        throw NSError(domain: "test", code: 1)
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

}


/// ssh itself failing, the way it does while the Mac is asleep: exit 255 and a
/// connection error, not a command that ran and failed.
private final class UnreachableRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        ("", "ssh: connect to host port 22: Operation timed out", 255)
    }
}
