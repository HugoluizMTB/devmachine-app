import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        recorded.append(args)
        lock.unlock()
        return ""
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.compactMap(\.last)
    }
}

@MainActor
final class EndSessionTests: XCTestCase {
    private let acme = Workspace(name: "acme", alias: "acme-devmachine")
    private var runner: RecordingRunner!
    private var model: AppModel!

    override func setUp() async throws {
        try await super.setUp()
        runner = RecordingRunner()
        model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [acme]
    }

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

    func testCommandWClosesTheTabAndEndsNothing() {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))

        XCTAssertEqual(model.handleCloseCommand(inMainWindow: true), .closeTab)
        XCTAssertNil(model.pendingEndSession)
        XCTAssertEqual(model.openTabs.items, [])
        XCTAssertNil(model.selection)
    }

    func testEndSessionAsksAboutTheOneRemoteSessionOnScreen() {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))

        XCTAssertTrue(model.requestEndSession())
        XCTAssertEqual(model.pendingEndSession, SessionEndRequest(
            item: .session(alias: acme.alias, name: "dash"), name: "dash", place: "acme"))
    }

    func testEndSessionAsksAboutTheOneLocalSessionOnScreenInLocal() {
        model.addLocalSession(path: "/Users/alice/dev/beta")
        model.selection = .localSession(name: "beta", path: "/Users/alice/dev/beta")

        XCTAssertTrue(model.requestEndSession())
        XCTAssertEqual(model.pendingEndSession?.name, "beta")
        XCTAssertEqual(model.pendingEndSession?.place, "Local")
    }

    func testDeletingAnUnselectedRemoteSessionAsksWithTheSameRequest() {
        model.clickSession(SessionRef(alias: acme.alias, name: "api"))

        model.askToEndSession(.session(alias: acme.alias, name: "dash"))

        XCTAssertEqual(model.pendingEndSession, SessionEndRequest(
            item: .session(alias: acme.alias, name: "dash"), name: "dash", place: "acme"))
    }

    func testAFocusedPreviewTabClosesInsteadOfEndingTheSession() {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))
        let tab = UUID()

        XCTAssertEqual(model.handleCloseCommand(inMainWindow: true, focusedPreview: tab), .closePreview(tab))
        XCTAssertNil(model.pendingEndSession)
    }

    func testAFocusedPreviewInAnotherWindowKeepsTheDefaultClose() {
        XCTAssertEqual(model.handleCloseCommand(inMainWindow: false, focusedPreview: UUID()), .closeWindow)
    }

    func testAPreviewTagNamesItsTab() {
        let tab = UUID()

        XCTAssertEqual(FocusedPreview.id(fromTag: FocusedPreview.tag(for: tab)), tab)
        XCTAssertNil(FocusedPreview.id(fromTag: FocusedTerminal.tag(for: .remote(alias: acme.alias, session: "dash"))))
        XCTAssertNil(FocusedPreview.id(fromTag: "preview:not-a-uuid"))
    }

    func testTheSelectedSessionOwnsThePreviews() {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))
        XCTAssertEqual(PreviewStore.shared.owner, SessionRef(alias: acme.alias, name: "dash"))

        model.addLocalSession(path: "/Users/alice/dev/beta")
        model.selection = .localSession(name: "beta", path: "/Users/alice/dev/beta")
        XCTAssertEqual(PreviewStore.shared.owner, SessionRef(alias: Workspace.local.alias, name: "beta"))

        model.selection = nil
        XCTAssertNil(PreviewStore.shared.owner)
    }

    func testAGridOfSessionsKeepsTheDefaultClose() {
        let dash = SessionRef(alias: acme.alias, name: "dash")
        let api = SessionRef(alias: acme.alias, name: "api")
        model.clickSession(dash)
        model.activePage = .sessionGrid([dash, api])

        XCTAssertEqual(model.handleCloseCommand(inMainWindow: true), .closeWindow)
        XCTAssertFalse(model.requestEndSession())
        XCTAssertNil(model.pendingEndSession)
    }

    func testSeveralSelectedSessionsAreNeverOfferedToEnd() {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))
        model.cmdClickSession(SessionRef(alias: acme.alias, name: "api"))

        XCTAssertFalse(model.requestEndSession())
        XCTAssertNil(model.pendingEndSession)
    }

    func testNoSelectionKeepsTheDefaultClose() {
        XCTAssertEqual(model.handleCloseCommand(inMainWindow: true), .closeWindow)
        XCTAssertNil(model.pendingEndSession)
    }

    func testAPageOverTheSessionKeepsTheDefaultClose() {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))
        model.activePage = .stats

        XCTAssertEqual(model.handleCloseCommand(inMainWindow: true), .closeWindow)
        XCTAssertFalse(model.requestEndSession())
    }

    func testAnotherWindowKeepsTheDefaultClose() {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))

        XCTAssertEqual(model.handleCloseCommand(inMainWindow: false), .closeWindow)
        XCTAssertNil(model.pendingEndSession)
    }

    func testTheOperatorSessionIsNeverOfferedToEnd() {
        model.selection = .localSession(name: Workspace.operatorSession, path: "/Users/alice/dev/ops")

        XCTAssertFalse(model.requestEndSession())
        XCTAssertNil(model.pendingEndSession)
        XCTAssertEqual(model.handleCloseCommand(inMainWindow: true), .closeTab, "its tab closes like any other")
    }

    func testConfirmingKillsThatRemoteSession() async throws {
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))
        model.requestEndSession()

        model.confirmEndSession()

        XCTAssertNil(model.pendingEndSession)
        try await waitUntil { self.runner.commands.contains(RemoteCommands.killSession(name: "dash")) }
        try await waitUntil { self.model.selection == nil }
    }

    func testConfirmingRemovesThatLocalSession() {
        model.addLocalSession(path: "/Users/alice/dev/beta")
        model.selection = .localSession(name: "beta", path: "/Users/alice/dev/beta")
        model.requestEndSession()

        model.confirmEndSession()

        XCTAssertNil(model.pendingEndSession)
        XCTAssertEqual(model.localSessions.map(\.handle), [Workspace.operatorSession])
        XCTAssertNil(model.selection)
    }

    func testCancellingEndsNothing() async throws {
        let item = SidebarItem.session(alias: acme.alias, name: "dash")
        model.clickSession(SessionRef(alias: acme.alias, name: "dash"))
        model.requestEndSession()

        model.cancelEndSession()
        model.confirmEndSession()

        XCTAssertNil(model.pendingEndSession)
        XCTAssertEqual(model.selection, item)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(runner.commands.contains(RemoteCommands.killSession(name: "dash")))
    }
}
