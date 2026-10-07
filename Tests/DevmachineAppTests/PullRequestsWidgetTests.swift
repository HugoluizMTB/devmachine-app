import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class PullRequestsWidgetTests: XCTestCase {
    private let type = "devmachine-app/pull-requests-panel"

    func testThePanelResolvesInBothSidebars() {
        for surface in ["sidebar", "context-sidebar"] {
            let board = StackBoard(surface: surface, entries: [StackEntry(id: "prs", type: type)])
            guard case let .ready(resolved)? = StackResolution.resolve(board.entries[0], on: board, catalog: nil) else {
                return XCTFail(surface)
            }
            XCTAssertEqual(resolved.viewKind, "app.pull-requests-panel")
        }
    }

    func testTheSidebarGalleryOffersItAndThePopoverStillPlacesIt() {
        XCTAssertTrue(StackGallery.entries(nil, surface: "sidebar").contains { $0.name == type })
        let widget = AppMenubarWidgets.catalogWidget("pull-requests-panel")
        XCTAssertEqual(widget?.places, ["menubar-panel"])
        XCTAssertEqual(widget?.fits, ["tabs", "canvas", "stack"])
    }

    func testOnHomeItResolvesFromThePackagesRelease() {
        let widget = CatalogWidget(
            name: type, fits: ["tabs", "canvas", "stack"], source: CatalogSource(name: "app/pull-requests-panel", every: "60s"),
            viewKind: "app.pull-requests-panel", sizes: ["large", "tall"], defaultSize: "large")
        let instance = BoardWidget(id: "prs", type: type, frame: BoardFrame(x: 0, y: 0, w: 320, h: 320), size: "large", z: 1)
        guard case .ready = WidgetResolution.resolve(instance, in: WidgetCatalog(engine: "1.5", packagesRelease: "r", widgets: [widget])) else {
            return XCTFail("expected ready")
        }
    }

    func testOnABoardItIsTitledPullRequests() {
        let board = StackBoard(surface: "sidebar", entries: [StackEntry(id: "prs", type: type)])
        let row = StackRowModel.make(
            entry: board.entries[0], index: 0, count: 1,
            resolution: StackResolution.resolve(board.entries[0], on: board, catalog: nil), approval: nil, catalog: nil)
        XCTAssertEqual(row.title, "Pull requests")
        XCTAssertEqual(
            MenubarTitles.title(board.entries[0], resolution: StackResolution.resolve(board.entries[0], on: board, catalog: nil), catalog: nil),
            "Pull Requests")
    }
}
