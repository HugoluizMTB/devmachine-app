import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class StackRowModelTests: XCTestCase {
    private let context = DefaultStackBoard.make(surface: "context-sidebar")

    private func model(
        _ entry: StackEntry, index: Int = 0, count: Int = 3, approval: ApprovalState? = nil, board: StackBoard? = nil
    ) -> StackRowModel {
        let board = board ?? context
        return StackRowModel.make(
            entry: entry, index: index, count: count, resolution: StackResolution.resolve(entry, on: board, catalog: nil),
            approval: approval, catalog: nil)
    }

    func testHeaderStylesKeepTodaysLook() {
        for kind in ["shortcuts", "monitors", "shells", "sub-agents", "todo", "pull-requests", "links"] {
            XCTAssertEqual(StackHeaderStyle.of(viewKind: "app.\(kind)"), .own, kind)
        }
        XCTAssertEqual(StackHeaderStyle.of(viewKind: "app.workspaces"), .bare)
        XCTAssertEqual(StackHeaderStyle.of(viewKind: "app.publish-port"), .bare)
        XCTAssertEqual(StackHeaderStyle.of(viewKind: "text"), .standard)
        XCTAssertEqual(StackHeaderStyle.of(viewKind: "monitors"), .standard)
        XCTAssertEqual(StackHeaderStyle.of(viewKind: "app.clock"), .standard)
    }

    func testEveryBuiltInViewHasAnAppViewKind() {
        XCTAssertEqual(Set(StackAppViewKind.allCases.map(\.viewKind)), AppStackWidgets.viewKinds)
        XCTAssertEqual(StackAppViewKind(viewKind: "app.publish-port"), .publishPort)
        XCTAssertNil(StackAppViewKind(viewKind: "publish-port"))
        XCTAssertNil(StackAppViewKind(viewKind: "app.clock"))
    }

    func testAnAppWidgetRowGrowsWithItsContentAndUsesTodaysTitle() {
        let row = model(context.entries[2], index: 2, count: 8)
        XCTAssertEqual(row.title, "MONITORS")
        XCTAssertEqual(row.header, .own)
        XCTAssertEqual(row.height, .content)
        XCTAssertEqual(row.sizeChoices, [.auto])
        XCTAssertTrue(row.canMoveUp)
        XCTAssertTrue(row.canMoveDown)
        let first = model(context.entries[0], index: 0, count: 8)
        XCTAssertFalse(first.canMoveUp)
        let last = model(context.entries[7], index: 7, count: 8)
        XCTAssertFalse(last.canMoveDown)
    }

    func testTheSidebarIsTheWorkspaceListByDefault() {
        let sidebar = DefaultStackBoard.make(surface: "sidebar")
        let row = StackRowModel.make(
            entry: sidebar.entries[0], index: 0, count: 1,
            resolution: StackResolution.resolve(sidebar.entries[0], on: sidebar, catalog: nil), approval: nil, catalog: nil)
        XCTAssertEqual(row.header, .bare)
        XCTAssertEqual(row.height, .content)
        XCTAssertEqual(row.title, "WORKSPACES")
        XCTAssertEqual(StackAppViewKind(rawValue: "workspaces"), .workspaces)
    }

    func testAPlaceholderTakesTwoRows() {
        let entry = StackEntry(id: "todo", type: "devmachine-app/todo")
        let row = model(entry, board: StackBoard(surface: "sidebar", entries: [entry]))
        XCTAssertEqual(row.title, "Cannot go here")
        XCTAssertEqual(row.height, .fixed(80))
        XCTAssertEqual(row.header, .standard)
    }

    func testAWaitingSourceWidgetLeavesRoomForTheApprovalCard() throws {
        let text = """
            format: 1
            surface: context-sidebar
            widgets:
              - id: here
                title: Here
                source: {kind: command, run: ls, args: ["{{context.path}}"], every: 30s}
                view: {kind: text}
                size: small

            """
        let board = try BoardCodec.decodeStack(text)
        XCTAssertEqual(model(board.entries[0], board: board).height, .fixed(80))
        XCTAssertEqual(model(board.entries[0], approval: .waiting(hash: "h"), board: board).height, .fixed(200))
        XCTAssertEqual(model(board.entries[0], approval: .denied(hash: "h"), board: board).height, .fixed(200))
        XCTAssertEqual(model(board.entries[0], approval: .allowed, board: board).height, .fixed(80))
        XCTAssertEqual(model(board.entries[0], board: board).title, "Here")
    }

    func testACollapsedRowSaysSo() {
        var entry = context.entries[3]
        entry.collapsed = true
        XCTAssertTrue(model(entry).isCollapsed)
        XCTAssertFalse(model(context.entries[3]).isCollapsed)
    }

    func testTheSizeMenuTicksTheDefaultPresetWhenTheEntryHasNoSize() {
        let disk = CatalogWidget(
            name: "acme/disk", fits: ["stack"], source: CatalogSource(name: "app/machines", every: "60s"),
            viewKind: "app.machines", sizes: ["small", "medium", "large"], defaultSize: "medium",
            surfaces: ["context-sidebar"])
        let catalog = WidgetCatalog(engine: "1.2", packagesRelease: "2026.10.07", widgets: [disk])
        let entry = StackEntry(id: "disk", type: "acme/disk")
        let board = StackBoard(surface: "context-sidebar", entries: [entry])
        let row = StackRowModel.make(
            entry: entry, index: 0, count: 1, resolution: StackResolution.resolve(entry, on: board, catalog: catalog),
            approval: nil, catalog: catalog)
        XCTAssertEqual(row.size, .preset("medium"))
        XCTAssertEqual(row.sizeChoices, [.preset("small"), .preset("medium"), .preset("large")])
        XCTAssertEqual(row.height, .fixed(80))
    }

    func testAWidgetThatCannotResolveKeepsTheSizeItsEntryNames() {
        let entry = StackEntry(id: "todo", type: "devmachine-app/todo", size: .auto)
        XCTAssertEqual(model(entry, board: StackBoard(surface: "sidebar", entries: [entry])).size, .auto)
    }

    func testADroppedRowLandsNextToTheNeighbourItCrossed() {
        let ids = ["a", "b", "c", "d"].map { StackEntry(id: $0, type: "x/\($0)") }
        XCTAssertEqual(StackDropTarget.position(of: "a", to: 2, in: ids), .after("c"))
        XCTAssertEqual(StackDropTarget.position(of: "d", to: 1, in: ids), .before("b"))
        XCTAssertNil(StackDropTarget.position(of: "b", to: 1, in: ids))
        XCTAssertNil(StackDropTarget.position(of: "a", to: 9, in: ids))
        XCTAssertNil(StackDropTarget.position(of: "z", to: 1, in: ids))
    }

    func testTheApprovalWarningNamesTheFileTheWidgetIsWrittenIn() {
        XCTAssertEqual(
            WidgetApprovalText.warning(surface: "home"),
            "It was written into home.yml, by you or an agent. Allow it only if you know what it does.")
        XCTAssertEqual(
            WidgetApprovalText.warning(surface: "sidebar"),
            "It was written into sidebar.yml, by you or an agent. Allow it only if you know what it does.")
        XCTAssertEqual(
            WidgetApprovalText.warning(surface: "context-sidebar"),
            "It was written into context-sidebar.yml, by you or an agent. Allow it only if you know what it does.")
    }

    func testABareRowShowsItsControlsOnlyWhileHoveredWithOptionHeld() {
        let row = model(context.entries[1], index: 1, count: 8)
        XCTAssertEqual(row.header, .bare)
        XCTAssertFalse(row.showsControls(hovering: false, optionHeld: false, dragging: false, canEdit: true))
        XCTAssertFalse(row.showsControls(hovering: true, optionHeld: false, dragging: false, canEdit: true))
        XCTAssertFalse(row.showsControls(hovering: false, optionHeld: true, dragging: false, canEdit: true))
        XCTAssertTrue(row.showsControls(hovering: true, optionHeld: true, dragging: false, canEdit: true))
        XCTAssertTrue(row.showsControls(hovering: false, optionHeld: false, dragging: true, canEdit: true))
        XCTAssertFalse(row.showsControls(hovering: true, optionHeld: true, dragging: false, canEdit: false))
    }

    func testARowWithItsOwnHeaderShowsItsControlsOnHover() {
        let row = model(context.entries[2], index: 2, count: 8)
        XCTAssertEqual(row.header, .own)
        XCTAssertFalse(row.showsControls(hovering: false, optionHeld: true, dragging: false, canEdit: true))
        XCTAssertTrue(row.showsControls(hovering: true, optionHeld: false, dragging: false, canEdit: true))
        XCTAssertTrue(row.showsControls(hovering: false, optionHeld: false, dragging: true, canEdit: true))
        XCTAssertFalse(row.showsControls(hovering: true, optionHeld: false, dragging: false, canEdit: false))
    }

    func testATitledRowAlwaysShowsItsControlsWhenTheBoardCanChange() {
        let entry = StackEntry(id: "todo", type: "devmachine-app/todo")
        let row = model(entry, board: StackBoard(surface: "sidebar", entries: [entry]))
        XCTAssertEqual(row.header, .standard)
        XCTAssertTrue(row.showsControls(hovering: false, optionHeld: false, dragging: false, canEdit: true))
        XCTAssertFalse(row.showsControls(hovering: true, optionHeld: true, dragging: true, canEdit: false))
        let collapsed = model(context.entries[1], index: 1, count: 8)
        XCTAssertTrue(
            collapsed.showsControls(hovering: false, optionHeld: false, dragging: false, canEdit: true, inTitleHeader: true))
    }

    func testTheSizeMenuNamesEachPresetWithItsRows() {
        XCTAssertEqual(StackWidgetMenuText.label(.auto), "Auto")
        XCTAssertEqual(StackWidgetMenuText.label(.preset("small")), "Small · 2 rows")
    }

    func testTheGalleryShowsAReasonEveryWidgetSharesOnceAtTheTop() {
        let widgets = AppStackWidgets.all
        XCTAssertEqual(WidgetGalleryReasons.shared(widgets) { _ in "Board is read-only" }, "Board is read-only")
        XCTAssertNil(WidgetGalleryReasons.shared(widgets) { $0.single ? "Already there" : nil })
        XCTAssertNil(WidgetGalleryReasons.shared([]) { _ in "Board is read-only" })
    }

    func testTheGalleryListsTheBuiltInWidgetsWhenTheCatalogDidNotLoad() {
        XCTAssertEqual(WidgetGalleryContent.of(hasCatalog: true, entries: 3, failure: "offline"), .list(failure: nil, loading: false))
        XCTAssertEqual(WidgetGalleryContent.of(hasCatalog: false, entries: 9, failure: "offline"), .list(failure: "offline", loading: false))
        XCTAssertEqual(WidgetGalleryContent.of(hasCatalog: false, entries: 9, failure: nil), .list(failure: nil, loading: true))
        XCTAssertEqual(WidgetGalleryContent.of(hasCatalog: false, entries: 0, failure: "offline"), .failure("offline"))
        XCTAssertEqual(WidgetGalleryContent.of(hasCatalog: false, entries: 0, failure: nil), .loading)
    }
}
