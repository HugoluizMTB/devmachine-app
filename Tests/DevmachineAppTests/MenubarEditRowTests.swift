import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

final class MenubarEditRowTests: XCTestCase {
    func testTheDefaultMenubarRowsReadAsTheBuiltIns() {
        let board = DefaultStackBoard.make(surface: "menubar")
        let rows = MenubarEditRow.rows(board: board, resolve: { StackResolution.resolve($0, on: board, catalog: nil) }, catalog: nil)
        XCTAssertEqual(rows.map(\.title), ["Devmachine mark", "Open pull requests"])
        XCTAssertEqual(rows.map(\.detail), [nil, nil])
        XCTAssertEqual(rows.map(\.canMoveUp), [false, true])
        XCTAssertEqual(rows.map(\.canMoveDown), [true, false])
    }

    func testARowThatCannotDrawSaysWhy() {
        let entry = StackEntry(id: "cpu", type: "acme/cpu")
        let board = StackBoard(surface: "menubar", entries: [entry])
        let refused = WidgetResolution.refused(type: "acme/cpu", reason: "the gauge view cannot be drawn in the menu bar")
        let rows = MenubarEditRow.rows(board: board, resolve: { _ in refused }, catalog: nil)
        XCTAssertEqual(rows.first?.detail, WidgetResolutionCopy.detail(refused, release: ""))
    }

    func testARowCarriesItsChoices() {
        let board = StackBoard(surface: "menubar-panel", entries: [
            StackEntry(id: "usage", type: "devmachine-app/usage"),
            StackEntry(id: "other", type: "acme/other"),
        ])
        let harness = ChoiceInput(name: "harness", input: CatalogInput(type: "choice", defaultValue: nil, summary: "", from: "harnesses"))!
        let rows = MenubarEditRow.rows(
            board: board, resolve: { _ in nil }, catalog: nil,
            choices: { $0.id == "usage" ? [harness] : [] })
        XCTAssertEqual(rows.map(\.choices), [[harness], []])
    }
}
