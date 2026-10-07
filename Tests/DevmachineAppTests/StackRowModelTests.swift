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
}
