import XCTest
@testable import DevmachineCore

final class HomeBoardCopyTests: XCTestCase {
    func testTheBannerNamesTheLine() {
        XCTAssertEqual(HomeBoardCopy.invalidTitle, "home.yml has a problem")
        XCTAssertEqual(
            HomeBoardCopy.invalidCause(BoardProblem(line: 12, message: "id \"clock\" is used twice")),
            "Line 12: id \"clock\" is used twice.")
        XCTAssertEqual(HomeBoardCopy.invalidCause(BoardProblem(line: nil, message: "not valid YAML: x")), "not valid YAML: x.")
        XCTAssertEqual(
            HomeBoardCopy.invalidNote, "Home keeps the last good layout and saves nothing until the file is fixed.")
    }

    func testAFailedPlacementsSaveSaysWhatWasLost() {
        XCTAssertEqual(
            HomeBoardCopy.placementsSaveFailed("disk full"), "Couldn't save which widgets were placed: disk full")
    }

    func testAddingIsBlockedUntilTheBoardCanBeEdited() {
        XCTAssertEqual(HomeBoardCopy.addBlocked(isOpen: false, canEdit: false), "Home is not ready yet.")
        XCTAssertEqual(HomeBoardCopy.addBlocked(isOpen: true, canEdit: false), HomeBoardCopy.invalidNote)
        XCTAssertNil(HomeBoardCopy.addBlocked(isOpen: true, canEdit: true))
    }
}
