import Combine
import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class GatedSessionSource: SessionListSource, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var listed: [String]
    private var calls = 0
    private var isOpen = false

    init(_ listed: [String]) {
        self.listed = listed
    }

    func set(_ names: [String]) {
        lock.lock()
        listed = names
        lock.unlock()
    }

    func release() {
        lock.lock()
        let wasOpen = isOpen
        isOpen = true
        lock.unlock()
        if !wasOpen { gate.signal() }
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession] {
        lock.lock()
        calls += 1
        let first = calls == 1
        let snapshot = listed
        lock.unlock()
        if first { gate.wait() }
        let names = first ? snapshot : { lock.lock(); defer { lock.unlock() }; return listed }()
        return names.map { TmuxSession(name: $0, windows: 1, harnesses: []) }
    }

    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot {
        LocalSessionSnapshot(sessions: [], harnesses: [:])
    }
}

private final class KillRunner: CommandRunner, @unchecked Sendable {
    private let exitCode: Int32
    private let stderr: String

    init(exitCode: Int32, stderr: String = "") {
        self.exitCode = exitCode
        self.stderr = stderr
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        ("", stderr, exitCode)
    }
}

@MainActor
final class SessionDeleteTests: XCTestCase {
    private let acme = Workspace(name: "acme", alias: "acme-devmachine")
    private let before = ["session-08", "session-09"]

    private func makeModel(source: GatedSessionSource, runner: CommandRunner) -> AppModel {
        addTeardownBlock { source.release() }
        let model = AppModel(
            store: SessionStore(runner: runner),
            services: DevmachineServices(
                workspaceSource: FixtureWorkspaceSource(), sessionSource: source,
                contextSource: FixtureContextSource()),
            detectSettings: { .empty },
            defaults: UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!)
        model.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev", hostAlias: "lab", publicIP: "203.0.113.10", baseDomain: "example.com")
        model.workspaces = [acme]
        model.sessionsByAlias[acme.alias] = before.map { TmuxSession(name: $0, windows: 1, harnesses: []) }
        return model
    }

    private func names(_ model: AppModel) -> [String] {
        model.sessionsByAlias[acme.alias]?.map(\.name).sorted() ?? []
    }

    private func waitFor(_ what: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { return XCTFail("never happened: \(what)") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testADeletedSessionStaysGoneWhenAnOlderListLandsAfterTheKill() async throws {
        let source = GatedSessionSource(before)
        let model = makeModel(source: source, runner: KillRunner(exitCode: 0))
        model.refresh(alias: acme.alias)
        try await waitFor("the first list starts") { source.callCount == 1 }

        source.set(["session-08"])
        model.deleteSession(alias: acme.alias, name: "session-09")
        try await waitFor("the row goes once the kill succeeds") { self.names(model) == ["session-08"] }
        var seen: [[String]] = []
        let watch = model.$sessionsByAlias.sink { seen.append(($0[self.acme.alias] ?? []).map(\.name)) }

        source.release()
        try await waitFor("the dropped refresh runs again") { source.callCount == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        watch.cancel()

        XCTAssertEqual(names(model), ["session-08"])
        XCTAssertFalse(seen.contains { $0.contains("session-09") }, "\(seen)")
    }

    func testABulkDeleteDropsTheRowsTheKillRemoved() async throws {
        let source = GatedSessionSource(before)
        let model = makeModel(source: source, runner: KillRunner(exitCode: 0))
        model.refresh(alias: acme.alias)
        try await waitFor("the first list starts") { source.callCount == 1 }

        source.set([])
        model.deleteSessions(before.map { SessionRef(alias: acme.alias, name: $0) })
        try await waitFor("the rows go once the kills succeed") { self.names(model).isEmpty }

        source.release()
        try await waitFor("the dropped refresh runs again") { source.callCount == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(names(model), [])
    }

    func testARenamedSessionDoesNotComeBackUnderItsOldName() async throws {
        let source = GatedSessionSource(before)
        let model = makeModel(source: source, runner: KillRunner(exitCode: 0))
        model.refresh(alias: acme.alias)
        try await waitFor("the first list starts") { source.callCount == 1 }

        source.set(["session-08", "web"])
        model.renameSession(alias: acme.alias, old: "session-09", new: "web")
        try await waitFor("the row takes the new name once tmux renames") {
            self.names(model) == ["session-08", "web"]
        }
        var seen: [[String]] = []
        let watch = model.$sessionsByAlias.sink { seen.append(($0[self.acme.alias] ?? []).map(\.name)) }

        source.release()
        try await waitFor("the dropped refresh runs again") { source.callCount == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        watch.cancel()

        XCTAssertEqual(names(model), ["session-08", "web"])
        XCTAssertFalse(seen.contains { $0.contains("session-09") }, "\(seen)")
    }

    func testAListWithoutEitherNameAfterTheRenameSucceededKeepsTheNewNamesPlace() async throws {
        let source = GatedSessionSource(["api", "dash"])
        source.release()
        let model = makeModel(source: source, runner: KillRunner(exitCode: 0))
        model.sessionsByAlias[acme.alias] = ["api", "dash", "web"].map { TmuxSession(name: $0, windows: 1, harnesses: []) }
        model.moveInSidebar(.session("web", in: acme.alias), over: .session("api", in: acme.alias))

        model.renameSession(alias: acme.alias, old: "web", new: "site")
        try await waitFor("the list the rename asked for lands") {
            source.callCount == 1 && self.names(model) == ["api", "dash"]
        }

        XCTAssertEqual(model.sidebarOrder.savedSessions[acme.alias], ["site", "api", "dash"])
    }

    func testAKillThatFailsKeepsTheRowAndSaysWhy() async throws {
        let source = GatedSessionSource(before)
        source.release()
        let model = makeModel(source: source, runner: KillRunner(exitCode: 1, stderr: "lost server"))

        model.deleteSession(alias: acme.alias, name: "session-09")
        try await waitFor("the failure is shown") {
            model.activeTasks.contains { $0.label.contains("Couldn't delete session-09") }
        }

        XCTAssertEqual(names(model), before)
        XCTAssertTrue(model.activeTasks.contains { $0.label.contains("lost server") })
    }

    func testAKillOfASessionTmuxNoLongerHasRemovesTheRowQuietly() async throws {
        for stderr in ["can't find session: session-09", "no server running on /tmp/tmux-501/default"] {
            let source = GatedSessionSource(before)
            source.release()
            let model = makeModel(source: source, runner: KillRunner(exitCode: 1, stderr: stderr))

            model.deleteSession(alias: acme.alias, name: "session-09")
            try await waitFor("the row goes: \(stderr)") { self.names(model) == ["session-08"] }

            XCTAssertFalse(model.activeTasks.contains { $0.label.contains("Couldn't") }, stderr)
        }
    }

    func testABulkKillOfSessionsTmuxNoLongerHasRemovesTheRowsQuietly() async throws {
        let source = GatedSessionSource(before)
        source.release()
        let model = makeModel(source: source, runner: KillRunner(exitCode: 1, stderr: "can't find session"))

        model.deleteSessions(before.map { SessionRef(alias: acme.alias, name: $0) })
        try await waitFor("the rows go") { self.names(model).isEmpty }

        XCTAssertFalse(model.activeTasks.contains { $0.label.contains("Couldn't") })
    }

    func testARenameThatFailsKeepsTheOldName() async throws {
        let source = GatedSessionSource(before)
        source.release()
        let model = makeModel(source: source, runner: KillRunner(exitCode: 1, stderr: "duplicate session: web"))

        model.renameSession(alias: acme.alias, old: "session-09", new: "web")
        try await waitFor("the failure is shown") {
            model.activeTasks.contains { $0.label.contains("Couldn't rename session-09") }
        }

        XCTAssertEqual(names(model), before)
        XCTAssertEqual(model.sessions(in: acme.alias).map(\.name), before)
    }

    func testARefreshAskedForWhileOneRunsRunsOnceMoreAfterIt() async throws {
        let source = GatedSessionSource(before)
        let model = makeModel(source: source, runner: KillRunner(exitCode: 0))
        model.refresh(alias: acme.alias)
        try await waitFor("the first list starts") { source.callCount == 1 }

        model.refresh(alias: acme.alias)
        model.refresh(alias: acme.alias)
        source.release()
        try await waitFor("the asked-for refresh runs") { source.callCount == 2 }
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(source.callCount, 2)
    }
}
