import XCTest
@testable import DevmachineCore

final class StackResolutionTests: XCTestCase {
    private let context = DefaultStackBoard.make(surface: "context-sidebar")
    private let sidebar = DefaultStackBoard.make(surface: "sidebar")

    private func ready(_ resolution: WidgetResolution?) -> ResolvedWidget? {
        if case let .ready(resolved)? = resolution { return resolved }
        return nil
    }

    func testTheAppWidgetsResolveWithoutTheCatalog() throws {
        for entry in context.entries + sidebar.entries {
            let board = entry.id == "workspaces" ? sidebar : context
            let resolved = try XCTUnwrap(ready(StackResolution.resolve(entry, on: board, catalog: nil)), entry.id)
            XCTAssertEqual(resolved.viewKind, "app.\(entry.id)")
            XCTAssertEqual(resolved.provider, AppStackWidgets.providers[entry.id])
        }
    }

    func testAnUnknownTypeWaitsForTheCatalogThenIsNotFound() {
        let entry = StackEntry(id: "disk", type: "acme/disk")
        let board = StackBoard(surface: "sidebar", entries: [entry])
        XCTAssertNil(StackResolution.resolve(entry, on: board, catalog: nil))
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board, catalog: CatalogFixtures.catalog([])), .notFound(type: "acme/disk"))
    }

    func testTheCatalogsOwnEntryWins() {
        var links = AppStackWidgets.catalogWidget("links")!
        links.summary = "From the release"
        let catalog = CatalogFixtures.catalog([links])
        XCTAssertEqual(StackCatalog.merged(catalog).widget(named: "devmachine-app/links")?.summary, "From the release")
        XCTAssertEqual(StackCatalog.merged(catalog).widgets.filter { $0.name == "devmachine-app/links" }.count, 1)
        XCTAssertNotNil(StackCatalog.merged(catalog).widget(named: "devmachine-app/workspaces"))
    }

    func testAWidgetThatDoesNotFitAStackKeepsItsPlace() {
        var clock = CatalogFixtures.clock
        clock.fits = ["canvas"]
        let entry = StackEntry(id: "clock", type: clock.name)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: StackBoard(surface: "sidebar", entries: [entry]), catalog: CatalogFixtures.catalog([clock])),
            .refused(type: clock.name, reason: "\(clock.name) does not fit the sidebar area: its fits has no stack"))
    }

    func testASingleWidgetTwiceDrawsOnlyTheFirst() {
        let second = StackEntry(id: "workspaces-2", type: "devmachine-app/workspaces", size: .auto)
        let board = StackBoard(surface: "sidebar", entries: sidebar.entries + [second])
        XCTAssertNotNil(ready(StackResolution.resolve(board.entries[0], on: board, catalog: nil)))
        XCTAssertEqual(StackResolution.resolve(second, on: board, catalog: nil), .refused(
            type: "devmachine-app/workspaces",
            reason: "devmachine-app/workspaces goes on a board once, and workspaces already has it"))
    }

    func testAutoNeedsAViewThatGrows() {
        var clock = CatalogFixtures.clock
        clock.fits = ["stack"]
        let entry = StackEntry(id: "clock", type: clock.name, size: .auto)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: StackBoard(surface: "sidebar", entries: [entry]), catalog: CatalogFixtures.catalog([clock])),
            .refused(type: clock.name, reason: "size auto follows the content, and the app.clock view does not grow: use small, medium"))
    }

    func testASizeTheWidgetDoesNotAllowIsRefused() {
        var clock = CatalogFixtures.clock
        clock.fits = ["stack"]
        clock.sizes = ["small", "medium"]
        let entry = StackEntry(id: "clock", type: clock.name, size: .preset("large"))
        XCTAssertEqual(
            StackResolution.resolve(entry, on: StackBoard(surface: "sidebar", entries: [entry]), catalog: CatalogFixtures.catalog([clock])),
            .refused(type: clock.name, reason: "size \"large\" in a sidebar is auto or one of small, medium"))
    }

    func testTheSidebarHasNoSessionForTheContextWidgets() {
        let entry = StackEntry(id: "todo", type: "devmachine-app/todo", size: .auto)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: StackBoard(surface: "sidebar", entries: [entry]), catalog: nil),
            .refused(type: "devmachine-app/todo", reason: "devmachine-app/todo needs context.session, which the sidebar area does not give"))
    }

    func testACatalogWidgetsOwnRequiredContextIsChecked() {
        var clock = CatalogFixtures.clock
        clock.fits = ["stack"]
        clock.context = ["path": "required"]
        let entry = StackEntry(id: "clock", type: clock.name)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: StackBoard(surface: "sidebar", entries: [entry]), catalog: CatalogFixtures.catalog([clock])),
            .refused(type: clock.name, reason: "\(clock.name) needs context.path, which the sidebar area does not give"))
        XCTAssertNotNil(ready(StackResolution.resolve(
            entry, on: StackBoard(surface: "context-sidebar", entries: [entry]), catalog: CatalogFixtures.catalog([clock]))))
    }

    func testAnInlineWidgetResolvesOnItsOwn() throws {
        let home = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: here
                title: Here
                source: {kind: command, run: ls, every: 30s}
                view: {kind: text}
                frame: {x: 24, y: 24, w: 320, h: 160}

            """)
        let entry = StackEntry(id: "here", type: "", inline: home.widgets[0].inline)
        let board = StackBoard(surface: "context-sidebar", entries: [entry])
        let resolved = try XCTUnwrap(ready(StackResolution.resolve(entry, on: board, catalog: nil)))
        XCTAssertEqual(resolved.title, "Here")
        XCTAssertEqual(resolved.source?.needsApproval, true)
    }

    func testTheGalleryListsWhatFitsTheAreaAndBlocksASecondSingle() {
        var clock = CatalogFixtures.clock
        clock.fits = ["canvas"]
        clock.surfaces = ["home"]
        let names = StackGallery.entries(CatalogFixtures.catalog([clock]), surface: "sidebar").map(\.name)
        XCTAssertTrue(names.contains("devmachine-app/workspaces"))
        XCTAssertTrue(names.contains("devmachine-app/publish-port"))
        XCTAssertFalse(names.contains("devmachine-app/todo"))
        XCTAssertFalse(names.contains(clock.name))
        let workspaces = AppStackWidgets.catalogWidget("workspaces")!
        XCTAssertEqual(StackGallery.blockedReason(for: workspaces, on: sidebar), "Already in the sidebar area")
        XCTAssertNil(StackGallery.blockedReason(for: workspaces, on: StackBoard(surface: "sidebar", entries: [])))
        XCTAssertNil(StackGallery.blockedReason(for: AppStackWidgets.catalogWidget("links")!, on: context))
    }

    func testAreaNamesAndFiles() {
        XCTAssertEqual(StackArea.name("sidebar"), "the sidebar area")
        XCTAssertEqual(StackArea.name("context-sidebar"), "the context-sidebar area")
        XCTAssertEqual(StackArea.sentenceName("context-sidebar"), "The context-sidebar area")
        XCTAssertEqual(StackArea.fileName("context-sidebar"), "context-sidebar.yml")
    }

    func testARefusedEntryNamesWhy() {
        let refused = WidgetResolution.refused(type: "acme/x", reason: "acme/x does not fit the sidebar area: its fits has no stack")
        XCTAssertEqual(WidgetResolutionCopy.title(refused), "Cannot go here")
        XCTAssertEqual(
            WidgetResolutionCopy.detail(refused, release: "r"), "acme/x does not fit the sidebar area: its fits has no stack.")
    }

    private func inlineGhostLoadEntry() throws -> (StackBoard, StackEntry) {
        let board = try BoardCodec.decodeStack("""
            format: 1
            surface: context-sidebar
            widgets:
              - id: load
                title: Load
                source: {kind: provider, name: ghost/load, target: {machine: main}, every: 60s}
                view: {kind: number, value: "{{json.load}}"}
                size: medium
            """)
        return (board, board.entries[0])
    }

    func testAnInlinePackageProviderInAStackIsCheckedAgainstTheCatalog() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widgets-list-engine-1.3.json")
        let catalog = try WidgetCatalog.decode(Data(contentsOf: url))
        let (board, entry) = try inlineGhostLoadEntry()
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board, catalog: catalog),
            .refused(type: entry.id, reason: "source.name ghost/load: no package ghost in the release or your own packages"))
        XCTAssertEqual(StackResolution.resolve(entry, on: board, catalog: nil), .waitingForCatalog(type: entry.id))
    }

    func testTheStackCatalogKeepsTheCLIListOfPackageProviders() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widgets-list-engine-1.3.json")
        let catalog = try WidgetCatalog.decode(Data(contentsOf: url))
        XCTAssertEqual(StackCatalog.merged(catalog).packageProviderIndex.isComplete, true)
    }
}
