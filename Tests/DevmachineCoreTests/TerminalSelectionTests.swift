import XCTest
@testable import DevmachineCore

final class TerminalPointerTests: XCTestCase {
    func testPressAndDragAlwaysSelectHere() {
        XCTAssertEqual(TerminalPointer.route(.press), .selection)
        XCTAssertEqual(TerminalPointer.route(.drag), .selection)
    }

    func testTheEndOfADragStaysHere() {
        XCTAssertEqual(TerminalPointer.route(.release(dragged: true, clickCount: 1, command: false)), .selection)
    }

    func testAPlainClickAlsoReachesTheProgram() {
        XCTAssertEqual(
            TerminalPointer.route(.release(dragged: false, clickCount: 1, command: false)),
            .selectionThenProgram)
    }

    func testDoubleAndTripleClicksSelectAWordAndALineHere() {
        XCTAssertEqual(TerminalPointer.route(.release(dragged: false, clickCount: 2, command: false)), .selection)
        XCTAssertEqual(TerminalPointer.route(.release(dragged: false, clickCount: 3, command: false)), .selection)
    }

    func testACommandClickOpensALinkAndNothingElse() {
        XCTAssertEqual(TerminalPointer.route(.release(dragged: false, clickCount: 1, command: true)), .selection)
    }

    func testTheWheelKeepsTheTerminalsOwnRule() {
        XCTAssertEqual(TerminalPointer.route(.wheel), .terminalDefault)
    }

    func testCopyOnSelectCopiesADragAWordAndALine() {
        XCTAssertTrue(TerminalPointer.copiesOnRelease(enabled: true, dragged: true, clickCount: 1, hasSelection: true))
        XCTAssertTrue(TerminalPointer.copiesOnRelease(enabled: true, dragged: false, clickCount: 2, hasSelection: true))
        XCTAssertTrue(TerminalPointer.copiesOnRelease(enabled: true, dragged: false, clickCount: 3, hasSelection: true))
    }

    func testCopyOnSelectLeavesTheClipboardAloneOtherwise() {
        XCTAssertFalse(TerminalPointer.copiesOnRelease(enabled: false, dragged: true, clickCount: 1, hasSelection: true))
        XCTAssertFalse(TerminalPointer.copiesOnRelease(enabled: true, dragged: false, clickCount: 1, hasSelection: true))
        XCTAssertFalse(TerminalPointer.copiesOnRelease(enabled: true, dragged: true, clickCount: 1, hasSelection: false))
    }
}

final class TerminalClipboardTests: XCTestCase {
    func testAFocusedPaneWritesTheDecodedText() {
        XCTAssertEqual(TerminalClipboard.text(fromWrite: Data("héllo".utf8), paneIsFocused: true), "héllo")
    }

    func testAPaneWithoutFocusCannotWrite() {
        XCTAssertNil(TerminalClipboard.text(fromWrite: Data("hello".utf8), paneIsFocused: false))
    }

    func testAWriteAboveTheCapIsDropped() {
        let atCap = Data(repeating: 0x61, count: TerminalClipboard.maxWriteBytes)
        XCTAssertEqual(TerminalClipboard.text(fromWrite: atCap, paneIsFocused: true)?.utf8.count,
                       TerminalClipboard.maxWriteBytes)
        let above = Data(repeating: 0x61, count: TerminalClipboard.maxWriteBytes + 1)
        XCTAssertNil(TerminalClipboard.text(fromWrite: above, paneIsFocused: true))
    }

    func testAnEmptyWriteDoesNotWipeTheClipboard() {
        XCTAssertNil(TerminalClipboard.text(fromWrite: Data(), paneIsFocused: true))
    }

    func testBytesThatAreNotTextAreDropped() {
        XCTAssertNil(TerminalClipboard.text(fromWrite: Data([0xFF, 0xFE, 0x00]), paneIsFocused: true))
    }
}

final class TerminalDragThresholdTests: XCTestCase {
    func testAShakyClickIsNotADrag() {
        XCTAssertFalse(TerminalPointer.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 11)))
    }

    func testMovingAFewPointsIsADrag() {
        XCTAssertTrue(TerminalPointer.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 14, y: 10)))
        XCTAssertTrue(TerminalPointer.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 4)))
    }
}
