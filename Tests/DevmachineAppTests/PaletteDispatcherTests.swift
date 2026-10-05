import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class SilentRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

@MainActor
private final class FakeStats: PaletteStatsControlling {
    var selected: [String] = []
    var refreshes = 0
    func select(_ name: String) { selected.append(name) }
    func refresh() { refreshes += 1 }
}

@MainActor
private final class FakeSites: PaletteSitesControlling {
    var preferred: [String] = []
    var refreshes = 0
    func prefer(machine: String) { preferred.append(machine) }
    func refresh() { refreshes += 1 }
}

@MainActor
private final class FakeHealth: PaletteHealthChecking {
    var runs = 0
    func run() { runs += 1 }
}

@MainActor
private final class FakeSavedCommands: PaletteSavedCommandRecording {
    var recorded: [(String, String)] = []
    func record(_ raw: String, for alias: String) -> String? {
        recorded.append((raw, alias))
        return raw
    }
}

@MainActor
private final class FakeSystem: PaletteSystem {
    var calls: [String] = []
    func openFilesWindow(alias: String) { calls.append("files:\(alias)") }
    func reveal(path: String) { calls.append("reveal:\(path)") }
    func open(_ url: URL) { calls.append("open:\(url.absoluteString)") }
    func quit() { calls.append("quit") }
    func chooseFileAndSend(to kind: TerminalKind) { calls.append("send") }
    func pickScreenColor(onCopy: @escaping @MainActor (String) -> Void) {
        calls.append("pick-color")
        onCopy("#1A334D")
    }
}

@MainActor
private final class FakeUpdates: PaletteUpdateChecking {
    var checks = 0
    func checkNow() { checks += 1 }
}

@MainActor
final class PaletteDispatcherTests: XCTestCase {
    private var model: AppModel!
    private var stats: FakeStats!
    private var sites: FakeSites!
    private var health: FakeHealth!
    private var saved: FakeSavedCommands!
    private var system: FakeSystem!
    private var updates: FakeUpdates!
    private var recents: PaletteRecentsStore!
    private var dispatcher: PaletteDispatcher!

    override func setUp() async throws {
        try await super.setUp()
        model = AppModel(store: SessionStore(runner: SilentRunner()))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        stats = FakeStats()
        sites = FakeSites()
        health = FakeHealth()
        saved = FakeSavedCommands()
        system = FakeSystem()
        updates = FakeUpdates()
        recents = PaletteRecentsStore(
            defaults: UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!)
        dispatcher = PaletteDispatcher(
            model: model, stats: stats, sites: sites, health: health,
            savedCommands: saved, updates: updates, recents: recents, system: system)
    }

    private func run(_ action: PaletteAction, id: String = "test") {
        dispatcher.perform(PaletteCommand(
            id: id, title: "t", subtitle: "", category: .action, systemImage: "circle", action: action))
    }

    func testRunningACommandClosesThePaletteAndRemembersIt() {
        model.showCommandPalette = true
        run(.showShortcuts, id: "go.shortcuts")
        XCTAssertFalse(model.showCommandPalette)
        XCTAssertTrue(model.showShortcuts)
        XCTAssertEqual(recents.mru.ids, ["go.shortcuts"])
    }

    func testEndSessionAsksAboutTheSessionOnScreen() {
        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        run(.endSession)
        XCTAssertEqual(model.pendingEndSession?.item, .session(alias: "acme-devmachine", name: "dash"))
    }

    func testGoHomeClearsThePageAndTheSelection() {
        model.activePage = .stats
        run(.goHome)
        XCTAssertNil(model.activePage)
        XCTAssertNil(model.selection)
    }

    func testStatsForAMachineSelectsItAndShowsStats() {
        run(.stats(machine: "main"))
        XCTAssertEqual(stats.selected, ["main"])
        XCTAssertEqual(model.activePage, .stats)
    }

    func testSubdomainsForAMachineSelectsItAndShowsSubdomains() {
        run(.subdomains(machine: "staging"))
        XCTAssertEqual(sites.preferred, ["staging"])
        XCTAssertEqual(model.activePage, .subdomains)
    }

    func testAddSubdomainOpensTheSheetOnThatMachine() {
        run(.addSubdomain(machine: "main"))
        XCTAssertEqual(sites.preferred, ["main"])
        XCTAssertEqual(model.activePage, .subdomains)
        XCTAssertTrue(model.pendingAddSubdomain)
    }

    func testNewWorkspaceOpensSettingsWorkspacesOnItsForm() {
        run(.newWorkspace)
        XCTAssertEqual(model.activePage, .setup)
        XCTAssertEqual(model.requestedSettingsSection, .workspaces)
        XCTAssertTrue(model.pendingNewWorkspace)
    }

    func testWorkspacesOpensSettingsWorkspaces() {
        run(.openSettings(.workspaces))
        XCTAssertEqual(model.activePage, .setup)
        XCTAssertEqual(model.requestedSettingsSection, .workspaces)
    }

    func testPublishAPortAsksForTheSheetOfThatWorkspace() {
        run(.publishPort(workspace: "acme"))
        XCTAssertEqual(model.pendingPublishWorkspace, "acme")
    }

    func testASettingsPaneOpensSettingsOnThatPane() {
        run(.openSettings(.appearance))
        XCTAssertEqual(model.activePage, .setup)
        XCTAssertEqual(model.requestedSettingsSection, .appearance)
    }

    func testThePackagesCommandOpensSettingsOnPackages() {
        run(.openSettings(.packages))
        XCTAssertEqual(model.activePage, .setup)
        XCTAssertEqual(model.requestedSettingsSection, .packages)
    }

    func testTheHealthCheckRunsAndShowsItsPane() {
        run(.runHealthCheck)
        XCTAssertEqual(health.runs, 1)
        XCTAssertEqual(model.activePage, .setup)
        XCTAssertEqual(model.requestedSettingsSection, .healthCheck)
    }

    func testCustomCommandOpensTheSheetForThatWorkspace() {
        run(.customCommand(alias: "acme-devmachine"))
        XCTAssertEqual(model.pendingCustomCommandAlias, "acme-devmachine")
    }

    func testANamedSessionOpensTheNewSessionSheet() {
        run(.newNamedSession(alias: "acme-devmachine"))
        XCTAssertEqual(model.pendingNewSessionAlias, "acme-devmachine")
    }

    func testASavedCommandIsRecordedAgain() {
        run(.runSavedCommand(alias: "local", command: "htop"))
        XCTAssertEqual(saved.recorded.map(\.0), ["htop"])
        XCTAssertEqual(saved.recorded.map(\.1), ["local"])
    }

    func testOpeningASessionSelectsIt() {
        run(.openSession(.session(alias: "acme-devmachine", name: "dash")))
        XCTAssertEqual(model.selection, .session(alias: "acme-devmachine", name: "dash"))
        XCTAssertEqual(model.selectedSessions, [SessionRef(alias: "acme-devmachine", name: "dash")])
    }

    func testRefreshReadsTheScreenThatIsShown() {
        model.activePage = .stats
        run(.refresh)
        XCTAssertEqual(stats.refreshes, 1)
        model.activePage = .subdomains
        run(.refresh)
        XCTAssertEqual(sites.refreshes, 1)
    }

    func testTogglesFlipTheSidebars() {
        let sidebar = model.sidebarCollapsed
        let context = model.contextCollapsed
        run(.toggleSidebar)
        run(.toggleContext)
        XCTAssertEqual(model.sidebarCollapsed, !sidebar)
        XCTAssertEqual(model.contextCollapsed, !context)
        run(.toggleSidebar)
        run(.toggleContext)
    }

    func testSystemActionsGoThroughTheSystem() throws {
        let docs = try XCTUnwrap(URL(string: "https://example.com/docs"))
        run(.openFiles(alias: "acme-devmachine"))
        run(.revealInFinder(path: "/Users/alice/notes"))
        run(.openURL(docs))
        run(.sendFile(.remote(alias: "acme-devmachine", session: "dash")))
        run(.quit)
        XCTAssertEqual(system.calls, [
            "files:acme-devmachine", "reveal:/Users/alice/notes", "open:https://example.com/docs",
            "send", "quit",
        ])
    }

    func testPickColorSamplesTheScreenAndSaysWhatWasCopied() {
        run(.pickColor)
        XCTAssertEqual(system.calls, ["pick-color"])
        XCTAssertEqual(model.activeTasks.map(\.label), ["Copied #1A334D"])
    }

    func testFindFileOpensTheFileFinder() {
        run(.findFile)
        XCTAssertTrue(model.showFileSearch)
    }

    func testCheckForUpdatesChecksAndShowsTheAboutPane() {
        run(.checkForUpdates)
        XCTAssertEqual(updates.checks, 1)
        XCTAssertEqual(model.requestedSettingsSection, .about)
    }
}
