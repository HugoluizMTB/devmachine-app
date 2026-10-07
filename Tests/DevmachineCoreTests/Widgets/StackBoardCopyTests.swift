import XCTest
@testable import DevmachineCore

final class StackBoardCopyTests: XCTestCase {
    func testResetCopyNamesTheArea() {
        XCTAssertEqual(StackBoardCopy.resetTitle("sidebar"), "Reset sidebar")
        XCTAssertEqual(StackBoardCopy.resetTitle("context-sidebar"), "Reset context sidebar")
        XCTAssertEqual(
            StackBoardCopy.resetConfirmation("context-sidebar"),
            "The context sidebar goes back to its default widgets. The current context-sidebar.yml is kept as context-sidebar.yml.bak.")
        XCTAssertEqual(StackBoardCopy.resetFailed("sidebar"), "Could not reset the sidebar")
        XCTAssertEqual(
            StackBoardCopy.resetHint,
            "The sidebar and the Context tab are lists of widgets. A reset brings back the default list of that area.")
    }

    func testTheBannerNamesTheFileAndTheLine() {
        XCTAssertEqual(
            StackBoardCopy.invalid(file: "sidebar.yml", problem: BoardProblem(line: 4, message: "unknown key \"x\" in a widget")),
            "sidebar.yml has a problem at line 4: unknown key \"x\" in a widget. The default layout shows until it is fixed; nothing is written meanwhile.")
    }
}
