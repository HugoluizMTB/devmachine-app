import XCTest
@testable import DevmachineCore

final class PRStateKindTests: XCTestCase {
    func testEveryRowStateFoldsIntoOneOfFourStates() {
        XCTAssertEqual(PRStateKind(.open), .open)
        XCTAssertEqual(PRStateKind(.approved), .open)
        XCTAssertEqual(PRStateKind(.changesRequested), .open)
        XCTAssertEqual(PRStateKind(.draft), .draft)
        XCTAssertEqual(PRStateKind(.merged), .merged)
        XCTAssertEqual(PRStateKind(.closed), .closed)
    }

    func testDraftIsNotOpenAndClosedIsNotMerged() {
        XCTAssertNotEqual(PRStateKind(.draft), PRStateKind(.open))
        XCTAssertNotEqual(PRStateKind(.closed), PRStateKind(.merged))
    }

    func testEachStateHasItsOwnSpokenLabel() {
        XCTAssertEqual(PRStateKind.open.accessibilityLabel, "Open pull request")
        XCTAssertEqual(PRStateKind.draft.accessibilityLabel, "Draft pull request")
        XCTAssertEqual(PRStateKind.merged.accessibilityLabel, "Merged pull request")
        XCTAssertEqual(PRStateKind.closed.accessibilityLabel, "Closed pull request")
    }

    func testTheHelpKeepsTheReviewTheIconNoLongerShows() {
        XCTAssertEqual(RowState.approved.help, "Open pull request · Approved")
        XCTAssertEqual(RowState.changesRequested.help, "Open pull request · Changes requested")
        XCTAssertEqual(RowState.open.help, "Open pull request")
        XCTAssertEqual(RowState.merged.help, "Merged pull request")
    }
}

final class ContrastTests: XCTestCase {
    func testBlackOnWhiteIsTwentyOneToOne() {
        XCTAssertEqual(Contrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
    }

    func testAColourAgainstItselfIsOneToOne() {
        XCTAssertEqual(Contrast.ratio(0x767E88, 0x767E88), 1, accuracy: 0.0001)
    }

    func testMidGrayMatchesTheKnownValue() {
        XCTAssertEqual(Contrast.ratio(0x767676, 0xFFFFFF), 4.54, accuracy: 0.01)
    }

    func testWhiteOverlayBlendsTowardWhite() {
        XCTAssertEqual(Contrast.white(opacity: 0, over: 0x0E1217), 0x0E1217)
        XCTAssertEqual(Contrast.white(opacity: 1, over: 0x0E1217), 0xFFFFFF)
        XCTAssertEqual(Contrast.white(opacity: 0.07, over: 0x0E1217), 0x1F2327)
    }
}
