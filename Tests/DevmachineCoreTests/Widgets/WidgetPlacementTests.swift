import XCTest
@testable import DevmachineCore

final class WidgetPlacementTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetPlacementTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let usage = [UsageHarness(harness: "claude", package: "claude-code"), UsageHarness(harness: "codex", package: "codex")]

    func testTheDefaultBoardIsTodaysHome() {
        let board = DefaultBoard.make(usage: usage)
        XCTAssertEqual(board.surface, "home")
        XCTAssertEqual(board.widgets.map(\.type), [
            "devmachine-app/clock", "devmachine-app/summary", "devmachine-app/machines", "claude-code/usage", "codex/usage",
        ])
        XCTAssertEqual(board.widgets.map(\.id), ["clock", "summary", "machines", "claude-usage", "codex-usage"])
        XCTAssertEqual(board.widgets[3].with, ["harness": .string("claude")])
        XCTAssertEqual(board.widgets[4].frame, BoardFrame(x: 24, y: 536, w: 320, h: 160))
        for widget in board.widgets {
            XCTAssertEqual(widget.frame.x % 8, 0)
            XCTAssertEqual(widget.frame.y % 8, 0)
        }
        for (index, a) in board.widgets.enumerated() {
            for b in board.widgets.dropFirst(index + 1) {
                XCTAssertFalse(a.frame.rect.intersects(b.frame.rect), "\(a.id) overlaps \(b.id)")
            }
        }
        XCTAssertEqual(Set(board.widgets.map(\.z)).count, board.widgets.count)
    }

    func testPlacementsSurviveARestart() throws {
        let file = WidgetPlacementsFile(fileURL: directory.appendingPathComponent("widget-placements.json"))
        XCTAssertEqual(file.load(), WidgetPlacements())
        var placements = WidgetPlacements()
        placements.insert("devmachine-app/clock", on: "home")
        try file.save(placements)
        XCTAssertTrue(file.load().contains("devmachine-app/clock", on: "home"))
        placements.reset("home")
        XCTAssertFalse(placements.contains("devmachine-app/clock", on: "home"))
    }

    func testAWidgetThatPlacesItselfJoinsOnceAtAFreeSpot() {
        let board = Board(surface: "home", widgets: [
            BoardWidget(id: "clock", type: "devmachine-app/clock", frame: BoardFrame(x: 24, y: 24, w: 320, h: 160), size: "medium", z: 1),
        ])
        let catalog = CatalogFixtures.catalog([CatalogFixtures.summary])
        let result = WidgetPlacer.place(
            on: board, catalog: catalog, placements: WidgetPlacements(), canvasWidth: 1280, isEligible: { _ in true })
        XCTAssertTrue(result.boardChanged)
        XCTAssertTrue(result.placementsChanged)
        let added = result.board.widgets.last
        XCTAssertEqual(added?.id, "devmachine-app-summary")
        XCTAssertEqual(added?.frame, BoardFrame(x: 352, y: 24, w: 640, h: 160))
        XCTAssertEqual(added?.size, "wide")
        XCTAssertEqual(added?.z, 2)
        XCTAssertTrue(result.placements.contains("devmachine-app/summary", on: "home"))
    }

    func testARemovedWidgetDoesNotComeBack() {
        var placements = WidgetPlacements()
        placements.insert("devmachine-app/summary", on: "home")
        let result = WidgetPlacer.place(
            on: Board(surface: "home", widgets: []), catalog: CatalogFixtures.catalog([CatalogFixtures.summary]),
            placements: placements, canvasWidth: 1280, isEligible: { _ in true })
        XCTAssertFalse(result.boardChanged)
        XCTAssertFalse(result.placementsChanged)
    }

    func testAWidgetAlreadyOnTheBoardIsOnlyRecorded() {
        let board = DefaultBoard.make(usage: [])
        let result = WidgetPlacer.place(
            on: board, catalog: CatalogFixtures.catalog([CatalogFixtures.clock]), placements: WidgetPlacements(),
            canvasWidth: 1280, isEligible: { _ in true })
        XCTAssertFalse(result.boardChanged)
        XCTAssertTrue(result.placements.contains("devmachine-app/clock", on: "home"))
    }

    func testUnavailableIneligibleOrElsewhereWidgetsWait() {
        var locked = CatalogFixtures.usage(package: "acme", harness: "acme")
        locked.available = false
        var sidebarOnly = CatalogFixtures.machines
        sidebarOnly.places = ["sidebar"]
        let codex = CatalogFixtures.usage(package: "codex", harness: "codex")
        let result = WidgetPlacer.place(
            on: Board(surface: "home", widgets: []), catalog: CatalogFixtures.catalog([locked, sidebarOnly, codex]),
            placements: WidgetPlacements(), canvasWidth: 1280,
            isEligible: { WidgetPlacer.harness(of: $0).map { $0 == "claude" } ?? true })
        XCTAssertEqual(result.board.widgets, [])
        XCTAssertFalse(result.placementsChanged)
    }

    func testAHarnessUsageWidgetNamesItsHarness() {
        XCTAssertEqual(WidgetPlacer.harness(of: CatalogFixtures.usage(package: "codex", harness: "codex")), "codex")
        XCTAssertNil(WidgetPlacer.harness(of: CatalogFixtures.clock))
        var fixed = CatalogFixtures.usage(package: "claude-code", harness: "unused")
        fixed.inputs = [:]
        fixed.source.with = ["harness": "claude"]
        XCTAssertEqual(WidgetPlacer.harness(of: fixed), "claude")
    }

    func testSavingOneSurfaceKeepsTheOthers() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("placements-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = WidgetPlacementsFile(fileURL: folder.appendingPathComponent("widget-placements.json"))
        var home = WidgetPlacements()
        home.insert("devmachine-app/clock", on: "home")
        try file.save(home, surface: "home")
        var stale = WidgetPlacements()
        stale.insert("devmachine-app/links", on: "context-sidebar")
        try file.save(stale, surface: "context-sidebar")
        let loaded = file.load()
        XCTAssertTrue(loaded.contains("devmachine-app/clock", on: "home"))
        XCTAssertTrue(loaded.contains("devmachine-app/links", on: "context-sidebar"))
        try file.save(WidgetPlacements(), surface: "home")
        XCTAssertFalse(file.load().contains("devmachine-app/clock", on: "home"))
        XCTAssertTrue(file.load().contains("devmachine-app/links", on: "context-sidebar"))
    }

    func testAStackPlacesAWidgetOnceAtTheEnd() {
        var disk = CatalogFixtures.machines
        disk.places = ["context-sidebar"]
        disk.surfaces = ["context-sidebar"]
        disk.fits = ["stack"]
        let board = DefaultStackBoard.make(surface: "context-sidebar")
        let first = StackPlacer.place(on: board, catalog: CatalogFixtures.catalog([disk]), placements: WidgetPlacements())
        XCTAssertTrue(first.boardChanged)
        XCTAssertEqual(first.board.entries.last?.type, disk.name)
        XCTAssertEqual(first.board.entries.last?.id, "machines")
        XCTAssertNil(first.board.entries.last?.size)
        XCTAssertTrue(first.placements.contains("devmachine-app/links", on: "context-sidebar"))
        var removed = first.board
        removed.remove("machines")
        let again = StackPlacer.place(on: removed, catalog: CatalogFixtures.catalog([disk]), placements: first.placements)
        XCTAssertFalse(again.boardChanged)
        XCTAssertFalse(again.placementsChanged)
    }

    func testAStackSkipsWhatDoesNotFitIt() {
        var canvasOnly = CatalogFixtures.machines
        canvasOnly.places = ["sidebar"]
        canvasOnly.fits = ["canvas"]
        let result = StackPlacer.place(
            on: StackBoard(surface: "sidebar", entries: []), catalog: CatalogFixtures.catalog([canvasOnly]),
            placements: WidgetPlacements())
        XCTAssertEqual(result.board.entries.map(\.type), ["devmachine-app/workspaces"])
        XCTAssertEqual(result.board.entries.first?.size, .auto)
    }
}
