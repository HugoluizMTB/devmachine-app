import XCTest
@testable import DevmachineCore

final class MenubarLabelModelTests: XCTestCase {
    private static let brand = CatalogWidget(
        name: "devmachine-app/brand", fits: ["slot"], source: CatalogSource(name: "app/brand", every: "60s"),
        viewKind: "app.brand", sizes: [], defaultSize: "", places: [], surfaces: ["menubar"])
    private static let openPullRequests = CatalogWidget(
        name: "devmachine-app/open-pull-requests", fits: ["slot"],
        source: CatalogSource(name: "app/open-pull-requests", every: "60s"), viewKind: "number", sizes: [],
        defaultSize: "", places: [], surfaces: ["menubar"],
        view: .object(["kind": .string("number"), "hide_zero": .bool(true)]))
    private static let catalog = CatalogFixtures.catalog([brand, openPullRequests])
    private static let defaultBoard = StackBoard(surface: "menubar", entries: [
        StackEntry(id: "brand", type: brand.name), StackEntry(id: "open-pull-requests", type: openPullRequests.name),
    ])

    private func items(openCount: Int, board: StackBoard = defaultBoard) -> [MenubarSlotItem] {
        MenubarLabelModel.items(MenubarLabelInputs.make(
            board: board, resolve: { StackResolution.resolve($0, on: board, catalog: Self.catalog) }, openCount: openCount,
            output: { _ in nil }, approval: { _, _ in .notNeeded }))
    }

    func testTheDefaultBoardDrawsTodaysLabel() {
        XCTAssertEqual(items(openCount: 0), [.brand])
        XCTAssertEqual(items(openCount: 7), [.brand, .text("7")])
        XCTAssertEqual(items(openCount: 1234), [.brand, .text("1234")])
    }

    func testTheOrderIsTheBoardsOrder() {
        var board = Self.defaultBoard
        board.moveUp("open-pull-requests")
        XCTAssertEqual(items(openCount: 3, board: board), [.text("3"), .brand])
    }

    func testTextShowsItsFirstLineCutAt24() {
        let long = MenubarSlotInput(viewKind: "text", output: .text("\n  load average: 0.42 0.40 0.39 and more  \nsecond"))
        XCTAssertEqual(MenubarLabelModel.item(long), .text("load average: 0.42 0.40…"))
        XCTAssertEqual(MenubarLabelModel.cut("load average: 0.42 0.40 0.39", limit: 24).count, 24)
        XCTAssertEqual(MenubarLabelModel.cut(String(repeating: "a", count: 24), limit: 24), String(repeating: "a", count: 24))
        XCTAssertEqual(MenubarLabelModel.cut(String(repeating: "a", count: 25), limit: 24), String(repeating: "a", count: 23) + "…")
        XCTAssertEqual(MenubarLabelModel.cut(String(repeating: "🙂", count: 30), limit: 24).count, 24)
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "text", output: .lines(["", "up 3 days"]))), .text("up 3 days"))
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "text", output: .ansi("\u{1B}[32mgreen\u{1B}[0m"))), .text("green"))
        XCTAssertNil(MenubarLabelModel.item(MenubarSlotInput(viewKind: "text", output: .text("  \n "))))
    }

    func testANumberUsesItsFormatAndUnit() {
        var view = WidgetView(kind: "number")
        view.format = .percent
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "number", view: view, output: .number(42))), .text("42%"))
        view.format = .plain
        view.unit = "GB"
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "number", view: view, output: .number(1.5))), .text("1.5 GB"))
    }

    func testHideZeroHidesAZeroButANumberWithoutItShowsZero() {
        var hidden = WidgetView(kind: "number")
        hidden.hideZero = true
        XCTAssertNil(MenubarLabelModel.item(MenubarSlotInput(viewKind: "number", view: hidden, output: .number(0))))
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "number", view: hidden, output: .number(2))), .text("2"))
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "number", output: .number(0))), .text("0"))
    }

    func testAStatusCarriesItsLevelAndASymbol() {
        var view = WidgetView(kind: "status")
        view.okRule = StatusRule.parse("== \"up\"")
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "status", view: view, output: .text("up"))), .status(.ok, "up"))
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "status", output: .status(code: 503, latency: 0.2))), .status(.bad, "503 · 200 ms"))
        XCTAssertEqual(MenubarLabelModel.symbol(.ok), "checkmark.circle.fill")
        XCTAssertEqual(MenubarLabelModel.symbol(.warn), "exclamationmark.triangle.fill")
        XCTAssertEqual(MenubarLabelModel.symbol(.bad), "xmark.octagon.fill")
        XCTAssertEqual(MenubarLabelModel.symbol(.neutral), "circle.fill")
    }

    func testAWaitingWidgetShowsAMarkAndADeniedOneNothing() {
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "text", approval: .waiting(hash: "a"))), .waiting)
        XCTAssertNil(MenubarLabelModel.item(MenubarSlotInput(viewKind: "text", output: .text("x"), approval: .denied(hash: "a"))))
        XCTAssertEqual(MenubarLabelModel.item(MenubarSlotInput(viewKind: "text", output: .text("x"), approval: .allowed)), .text("x"))
    }

    func testAnEmptyLabelFallsBackToTheMark() {
        XCTAssertEqual(MenubarLabelModel.items([]), [.brand])
        var hidden = WidgetView(kind: "number")
        hidden.hideZero = true
        XCTAssertEqual(MenubarLabelModel.items([MenubarSlotInput(viewKind: "number", view: hidden, output: .number(0))]), [.brand])
        XCTAssertEqual(items(openCount: 5, board: StackBoard(surface: "menubar", entries: [])), [.brand])
    }

    func testAValueThatCannotBeReadDrawsNothing() {
        XCTAssertNil(MenubarLabelModel.item(MenubarSlotInput(viewKind: "number", output: .text("n/a"))))
        XCTAssertNil(MenubarLabelModel.item(MenubarSlotInput(viewKind: "gauge", output: .number(3))))
        XCTAssertNil(MenubarLabelModel.item(MenubarSlotInput(viewKind: "text")))
    }

    func testAnEntryThatIsNotReadyDrawsNothing() {
        let board = StackBoard(surface: "menubar", entries: [StackEntry(id: "x", type: "acme/x")])
        XCTAssertEqual(MenubarLabelModel.items(MenubarLabelInputs.make(
            board: board, resolve: { _ in .notFound(type: "acme/x") }, openCount: 9,
            output: { _ in .text("never") }, approval: { _, _ in .notNeeded })), [.brand])
    }

    func testTheViewOfAnAppProviderWidgetIsReadFromItsCatalogEntry() {
        var widget = Self.openPullRequests
        widget.view = .object(["kind": .string("number"), "unit": .string("open"), "hide_zero": .bool(true)])
        let entry = StackEntry(id: "prs", type: widget.name)
        let board = StackBoard(surface: "menubar", entries: [entry])
        guard case let .ready(resolved)? = StackResolution.resolve(entry, on: board, catalog: CatalogFixtures.catalog([widget]))
        else { return XCTFail("not ready") }
        XCTAssertEqual(MenubarLabelModel.view(of: resolved)?.unit, "open")
        XCTAssertEqual(MenubarLabelModel.view(of: resolved)?.hideZero, true)
        XCTAssertEqual(MenubarLabelModel.items(MenubarLabelInputs.make(
            board: board, resolve: { _ in .ready(resolved) }, openCount: 2,
            output: { _ in nil }, approval: { _, _ in .notNeeded })), [.text("2 open")])
    }
}
