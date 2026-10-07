import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ListedSessionSource: SessionListSource, @unchecked Sendable {
    private let lock = NSLock()
    private var listed: [String: [String]]
    private var failing = false

    init(_ listed: [String: [String]]) {
        self.listed = listed
    }

    func set(_ names: [String], for alias: String) {
        lock.lock()
        defer { lock.unlock() }
        listed[alias] = names
    }

    func fail() {
        lock.lock()
        defer { lock.unlock() }
        failing = true
    }

    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession] {
        lock.lock()
        defer { lock.unlock() }
        if failing { throw SessionStoreError(failure: .unreachable, stderr: "") }
        return (listed[workspace.alias] ?? []).map { TmuxSession(name: $0, windows: 1, harnesses: []) }
    }

    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot {
        LocalSessionSnapshot(sessions: [], harnesses: [:])
    }
}

private struct SilentRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

private final class FailingWorkspaceSource: WorkspaceSource {
    func workspaces(resolveAlias: (String) -> String) throws -> [Workspace] {
        throw CocoaError(.fileReadUnknown)
    }
}

@MainActor
final class SidebarOrderModelTests: XCTestCase {
    private let acme = Workspace(name: "acme", alias: "acme-devmachine")
    private let globex = Workspace(name: "globex", alias: "globex-devmachine")
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")
    }

    private func makeModel(
        sessions: ListedSessionSource = ListedSessionSource([:]),
        workspaces: any WorkspaceSource = FixtureWorkspaceSource()
    ) -> AppModel {
        let model = AppModel(
            store: SessionStore(runner: SilentRunner()),
            services: DevmachineServices(
                workspaceSource: workspaces, sessionSource: sessions, contextSource: FixtureContextSource()),
            detectSettings: { .empty },
            defaults: defaults)
        model.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev", hostAlias: "lab", publicIP: "203.0.113.10", baseDomain: "example.com")
        model.workspaces = [acme, globex]
        return model
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func poll(_ model: AppModel, _ alias: String, until names: [String]) async throws {
        model.refresh(alias: alias)
        try await waitFor { model.sessionsByAlias[alias]?.map(\.name).sorted() == names.sorted() }
    }

    func testLocalStaysLastUntilItIsMoved() {
        let model = makeModel()
        XCTAssertEqual(model.sidebarWorkspaces.map(\.name), ["acme", "globex", "Local"])

        model.moveInSidebar(.workspace("local"), over: .workspace(acme.alias))

        XCTAssertEqual(model.sidebarWorkspaces.map(\.name), ["Local", "acme", "globex"])
    }

    func testTheOrderSurvivesARelaunch() {
        makeModel().moveInSidebar(.workspace(globex.alias), over: .session("dash", in: acme.alias))

        XCTAssertEqual(makeModel().sidebarWorkspaces.map(\.name), ["globex", "acme", "Local"])
    }

    func testRemoteSessionsMoveInsideTheirWorkspace() async throws {
        let model = makeModel(sessions: ListedSessionSource([acme.alias: ["api", "dash", "web"]]))
        try await poll(model, acme.alias, until: ["api", "dash", "web"])

        model.moveInSidebar(.session("web", in: acme.alias), over: .session("api", in: acme.alias))

        XCTAssertEqual(model.sessions(in: acme.alias).map(\.name), ["web", "api", "dash"])
    }

    func testLocalSessionsMoveToo() {
        let model = makeModel()
        model.addLocalSession(path: "/Users/alice/dev/acme")
        defer { model.removeLocalSession(handle: "acme") }

        model.moveInSidebar(.session("acme", in: "local"), over: .session("Operator", in: "local"))

        XCTAssertEqual(model.localSessions.map(\.handle), ["acme", "Operator"])
    }

    func testASessionNeverMovesToAnotherWorkspace() async throws {
        let model = makeModel(sessions: ListedSessionSource([acme.alias: ["api", "dash"]]))
        try await poll(model, acme.alias, until: ["api", "dash"])

        let action = model.moveInSidebar(.session("dash", in: acme.alias), over: .session("Operator", in: "local"))

        XCTAssertEqual(action, .refuse)
        XCTAssertEqual(model.sidebarOrder, SidebarOrder())
        XCTAssertEqual(model.localSessions.map(\.handle), ["Operator"])
    }

    func testHidingAWorkspaceForgetsItsOrder() {
        let model = makeModel()
        model.moveInSidebar(.workspace(globex.alias), over: .workspace(acme.alias))
        model.moveInSidebar(.session("b", in: globex.alias), over: .session("a", in: globex.alias))

        model.settings?.hiddenWorkspaces = [globex.alias]
        model.applyHiddenWorkspaces()
        model.settings?.hiddenWorkspaces = []

        XCTAssertEqual(model.sidebarWorkspaces.map(\.name), ["acme", "Local", "globex"])
        XCTAssertNil(model.sidebarOrder.savedSessions[globex.alias])
    }

    func testAWorkspaceGoneFromTheConfigurationIsForgotten() {
        let model = makeModel(workspaces: FixtureWorkspaceSource(values: [acme]))
        model.moveInSidebar(.workspace(globex.alias), over: .workspace(acme.alias))

        model.loadWorkspaces(detected: .empty)

        XCTAssertFalse(model.sidebarOrder.savedWorkspaces.contains(globex.alias))
        XCTAssertTrue(model.sidebarOrder.savedWorkspaces.contains(acme.alias))
    }

    func testAnUnreadableConfigurationForgetsNothing() {
        let model = makeModel(workspaces: FailingWorkspaceSource())
        model.moveInSidebar(.workspace(globex.alias), over: .workspace(acme.alias))
        let saved = model.sidebarOrder

        model.loadWorkspaces(detected: .empty)

        XCTAssertEqual(model.sidebarOrder, saved)
    }

    func testASessionGoneFromAPollIsForgotten() async throws {
        let source = ListedSessionSource([acme.alias: ["api", "dash", "web"]])
        let model = makeModel(sessions: source)
        try await poll(model, acme.alias, until: ["api", "dash", "web"])
        model.moveInSidebar(.session("web", in: acme.alias), over: .session("api", in: acme.alias))

        source.set(["api", "dash"], for: acme.alias)
        try await poll(model, acme.alias, until: ["api", "dash"])

        XCTAssertEqual(model.sidebarOrder.savedSessions[acme.alias], ["api", "dash"])
    }

    func testAFailedPollForgetsNothing() async throws {
        let source = ListedSessionSource([acme.alias: ["api", "dash"]])
        let model = makeModel(sessions: source)
        try await poll(model, acme.alias, until: ["api", "dash"])
        model.moveInSidebar(.session("dash", in: acme.alias), over: .session("api", in: acme.alias))
        let saved = model.sidebarOrder

        source.fail()
        model.refresh(alias: acme.alias)
        try await waitFor { model.offlineAliases.contains(self.acme.alias) || model.isPollingPaused(alias: self.acme.alias) }

        XCTAssertEqual(model.sidebarOrder, saved)
    }

    func testARenamedSessionKeepsItsPlace() async throws {
        let source = ListedSessionSource([acme.alias: ["api", "dash", "web"]])
        let model = makeModel(sessions: source)
        try await poll(model, acme.alias, until: ["api", "dash", "web"])
        model.moveInSidebar(.session("web", in: acme.alias), over: .session("api", in: acme.alias))

        source.set(["api", "dash", "site"], for: acme.alias)
        model.renameSession(alias: acme.alias, old: "web", new: "site")
        try await poll(model, acme.alias, until: ["api", "dash", "site"])

        XCTAssertEqual(model.sessions(in: acme.alias).map(\.name), ["site", "api", "dash"])
    }

    func testRemovingALocalSessionForgetsItsPlace() {
        let model = makeModel()
        model.addLocalSession(path: "/Users/alice/dev/acme")
        model.moveInSidebar(.session("acme", in: "local"), over: .session("Operator", in: "local"))

        model.removeLocalSession(handle: "acme")

        XCTAssertEqual(model.sidebarOrder.savedSessions["local"], ["Operator"])
    }

    func testNavigationAndThePaletteFollowTheSidebar() async throws {
        let model = makeModel(sessions: ListedSessionSource([acme.alias: ["api", "dash"]]))
        try await poll(model, acme.alias, until: ["api", "dash"])
        model.moveInSidebar(.workspace("local"), over: .workspace(acme.alias))
        model.moveInSidebar(.session("dash", in: acme.alias), over: .session("api", in: acme.alias))

        model.moveToNextSession()
        XCTAssertEqual(model.selection, .localSession(name: "Operator", path: model.localSessions[0].path))
        model.moveToNextSession()
        XCTAssertEqual(model.selection, .session(alias: acme.alias, name: "dash"))
        XCTAssertEqual(model.flattenedSessions().map(\.name), ["dash", "api"])
        XCTAssertEqual(model.paletteItems().prefix(3).map(\.title), ["Operator", "dash", "api"])
    }

    func testAPollBeforeTmuxRenamesKeepsTheNewNamesPlace() async throws {
        let source = ListedSessionSource([acme.alias: ["api", "dash", "web"]])
        let model = makeModel(sessions: source)
        try await poll(model, acme.alias, until: ["api", "dash", "web"])
        model.moveInSidebar(.session("web", in: acme.alias), over: .session("api", in: acme.alias))

        model.renameSession(alias: acme.alias, old: "web", new: "site")
        source.set(["api", "dash"], for: acme.alias)
        try await poll(model, acme.alias, until: ["api", "dash"])

        XCTAssertEqual(model.sidebarOrder.savedSessions[acme.alias], ["site", "api", "dash"])
    }
}
