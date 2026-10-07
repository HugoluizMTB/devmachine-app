import XCTest
@testable import DevmachineApp
@testable import DevmachineCore
import HarnessUsageKit

private final class QuietRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

@MainActor
final class MenubarControllerTests: XCTestCase {
    private var root: URL!
    private var command: ScriptedSourceRunner!
    private var launcher: AppFakeLauncher!
    private var menubars: [MenubarController] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MenubarControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        command = ScriptedSourceRunner([.success(.output(.text("0.42\nmore")))])
        launcher = AppFakeLauncher()
    }

    override func tearDown() async throws {
        for menubar in menubars {
            menubar.setPanelOpen(false)
            if menubar.slots.hasSources { menubar.slots.sources.stop() }
            if menubar.panel.hasSources { menubar.panel.sources.stop() }
        }
        menubars.removeAll()
        command.release()
        launcher.releaseAll()
        try? FileManager.default.removeItem(at: root)
    }

    private var config: String { root.appendingPathComponent("config").path }
    private func file(_ surface: String) -> URL { BoardFiles.url(configDirectory: config, surface: surface) }

    private func write(_ text: String, _ surface: String) throws {
        try FileManager.default.createDirectory(at: file(surface).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file(surface))
    }

    private func placeBuiltIns() throws {
        var placements = WidgetPlacements()
        for widget in AppMenubarWidgets.all {
            for surface in widget.places { placements.insert(widget.name, on: surface) }
        }
        let file = WidgetPlacementsFile(fileURL: root.appendingPathComponent("placements.json"))
        for surface in DefaultStackBoard.menubarSurfaces { _ = try file.save(placements, surface: surface) }
    }

    private func widget(_ name: String, fits: String, surface: String) -> CatalogWidget {
        var widget = CatalogWidget(
            name: name, fits: [fits],
            source: CatalogSource(raw: .object([
                "kind": .string("command"), "run": .string("uptime"), "every": .string("60s"),
            ])),
            viewKind: "text", sizes: [], defaultSize: "", places: [], surfaces: [surface])
        widget.view = .object(["kind": .string("text")])
        return widget
    }

    private func board(_ surface: String, store: WidgetCatalogStore) -> StackBoardController {
        let environment = SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: [:]) },
            localEnvironment: [:], home: "/Users/alice", isExecutable: { _ in true })
        let sources = WidgetSourceController(
            runners: SourceRunners(command: command, url: command, prompt: command, session: command, launcher: launcher, environment: environment),
            approvalsFile: WidgetApprovalsFile(fileURL: root.appendingPathComponent("approvals.json")),
            historyStore: SparklineHistoryStore(directory: root.appendingPathComponent("history")), surface: surface,
            isDemo: false, startsTimer: false)
        let controller = StackBoardController(
            surface: surface, placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("placements.json")),
            catalog: store, configPath: { nil }, sources: sources)
        controller.open(configDirectory: config)
        return controller
    }

    private func makeMenubar(_ widgets: [CatalogWidget] = []) -> (MenubarController, PRStore) {
        let catalog = WidgetCatalog(engine: "1.4", packagesRelease: "2026.10.07", widgets: widgets)
        let store = WidgetCatalogStore(read: { catalog })
        store.seed(catalog)
        let menubar = MenubarController(slots: board("menubar", store: store), panel: board("menubar-panel", store: store))
        let prs = PRStore(client: GHClient(runner: QuietRunner()))
        let usage = HarnessUsageStore(providers: [])
        menubar.start(prs: prs, providers: AppWidgetProviders(usage: usage, stats: StatsStore(cli: { throw CancellationError() }, cache: nil, tickInterval: nil), prs: prs))
        menubars.append(menubar)
        return (menubar, prs)
    }

    func testTheDefaultBoardsDrawTodaysLabel() throws {
        let (menubar, prs) = makeMenubar()
        XCTAssertEqual(try String(contentsOf: file("menubar"), encoding: .utf8), BoardCodec.encodeStack(DefaultStackBoard.make(surface: "menubar")))
        XCTAssertEqual(try String(contentsOf: file("menubar-panel"), encoding: .utf8), BoardCodec.encodeStack(DefaultStackBoard.make(surface: "menubar-panel")))
        prs.openCount = 0
        menubar.refresh()
        XCTAssertEqual(menubar.label.items, [.brand])
        prs.openCount = 3
        menubar.refresh()
        XCTAssertEqual(menubar.label.items, [.brand, .text("3")])
    }

    func testThePullRequestCountFollowsOnItsOwn() async {
        let (menubar, prs) = makeMenubar()
        prs.openCount = 5
        await waitUntil { menubar.label.items == [.brand, .text("5")] }
    }

    func testLabelSourcesRunWithNoWindow() async throws {
        try placeBuiltIns()
        try write("format: 1\nsurface: menubar\nwidgets:\n  - id: load\n    type: acme/load\n", "menubar")
        let (menubar, _) = makeMenubar([widget("acme/load", fits: "slot", surface: "menubar")])
        await waitUntil { self.command.calls == 1 }
        XCTAssertFalse(menubar.isPanelOpen)
        await waitUntil { menubar.label.items == [.text("0.42")] }
    }

    func testPanelSourcesRunOnlyWhileOpenAndOnlyTheTabOnScreen() async throws {
        command = ScriptedSourceRunner([.success(.output(.text("log")))], gated: true)
        try write("""
            format: 1
            surface: menubar-panel
            widgets:
              - id: one
                type: acme/one
              - id: two
                type: acme/two

            """, "menubar-panel")
        let (menubar, _) = makeMenubar([
            widget("acme/one", fits: "tabs", surface: "menubar-panel"), widget("acme/two", fits: "tabs", surface: "menubar-panel"),
        ])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        menubar.showTab("two")
        menubar.setPanelOpen(true)
        await waitUntil { self.command.calls == 1 }
        XCTAssertEqual(command.requests[0].instanceID, "two")
        XCTAssertTrue(menubar.panel.sources.state("two").isRunning)
        menubar.setPanelOpen(false)
        XCTAssertFalse(menubar.panel.sources.state("two").isRunning)
        command.release()
        await waitUntil { self.command.cancelled == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
    }

    func testALabelWidgetWaitingForApprovalShowsAMarkAndIsListed() async throws {
        try placeBuiltIns()
        try write("""
            format: 1
            surface: menubar
            widgets:
              - id: brand
                type: devmachine-app/brand
              - id: mine
                title: Mine
                source: {kind: command, run: uptime, every: 30s}
                view: {kind: text}

            """, "menubar")
        let (menubar, _) = makeMenubar()
        await waitUntil { menubar.label.items == [.brand, .waiting] }
        XCTAssertEqual(menubar.approvals.map(\.id), ["mine"])
        XCTAssertEqual(menubar.approvals.first?.title, "Mine")
        guard case let .waiting(hash) = menubar.slots.sources.approvalState("mine") else { return XCTFail("not waiting") }
        menubar.slots.sources.approve("mine", hash: hash)
        await waitUntil { menubar.label.items == [.brand, .text("0.42")] }
        XCTAssertEqual(menubar.approvals, [])
    }

    func testADeniedLabelWidgetDrawsNothingAndStaysListed() async throws {
        try placeBuiltIns()
        try write("""
            format: 1
            surface: menubar
            widgets:
              - id: mine
                title: Mine
                source: {kind: command, run: uptime, every: 30s}
                view: {kind: text}

            """, "menubar")
        let (menubar, _) = makeMenubar()
        await waitUntil { menubar.label.items == [.waiting] }
        guard case let .waiting(hash) = menubar.slots.sources.approvalState("mine") else { return XCTFail("not waiting") }
        menubar.slots.sources.deny("mine", hash: hash)
        await waitUntil { menubar.label.items == [.brand] }
        XCTAssertEqual(menubar.approvals.map(\.id), ["mine"])
        XCTAssertEqual(command.calls, 0)
    }

    func testAnEditElsewhereIsPickedUp() async throws {
        let (menubar, prs) = makeMenubar()
        prs.openCount = 2
        menubar.refresh()
        try write("format: 1\nsurface: menubar\nwidgets:\n  - id: open-pull-requests\n    type: devmachine-app/open-pull-requests\n", "menubar")
        menubar.reload()
        await waitUntil { menubar.label.items == [.text("2")] }
    }

    func testRemovingEverySlotLeavesTheMark() async throws {
        let (menubar, prs) = makeMenubar()
        prs.openCount = 4
        menubar.slots.remove("brand")
        menubar.slots.remove("open-pull-requests")
        await waitUntil { menubar.label.items == [.brand] }
        menubar.slots.store?.flush()
        XCTAssertEqual(try String(contentsOf: file("menubar"), encoding: .utf8), "format: 1\nsurface: menubar\nwidgets: []\n")
    }

    func testAFullMenubarRefusesAnAdd() throws {
        let (menubar, _) = makeMenubar([widget("acme/load", fits: "slot", surface: "menubar")])
        let load = try XCTUnwrap(menubar.slots.galleryEntries().first { $0.name == "acme/load" })
        XCTAssertTrue(menubar.slots.add(load))
        let other = widget("acme/other", fits: "slot", surface: "menubar")
        XCTAssertEqual(menubar.slots.addBlockedReason(for: other), "The menu bar holds 3 widgets")
        XCTAssertFalse(menubar.slots.add(other))
    }
}
