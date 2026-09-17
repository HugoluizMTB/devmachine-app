import XCTest
import AppKit
@testable import DevmachineApp

final class TerminalKeyboardTests: XCTestCase {
    func testOptionAloneComposesInsteadOfActingAsMeta() {
        XCTAssertFalse(TerminalKeyboard.optionActsAsMeta(for: [.option]))
        XCTAssertFalse(TerminalKeyboard.optionActsAsMeta(for: [.option, .shift]))
        XCTAssertFalse(TerminalKeyboard.optionActsAsMeta(for: []))
    }

    func testOptionWithAFunctionKeyActsAsMeta() {
        XCTAssertTrue(TerminalKeyboard.optionActsAsMeta(for: [.option, .function]))
        XCTAssertTrue(TerminalKeyboard.optionActsAsMeta(for: [.option, .function, .numericPad]))
        XCTAssertFalse(TerminalKeyboard.optionActsAsMeta(for: [.function]))
    }

    func testShiftReturnSendsNewline() {
        XCTAssertTrue(TerminalKeyboard.sendsNewline(keyCode: 36, flags: [.shift]))
        XCTAssertEqual(TerminalKeyboard.newlineBytes, [0x0A])
    }

    func testPlainReturnStillSubmits() {
        XCTAssertFalse(TerminalKeyboard.sendsNewline(keyCode: 36, flags: []))
    }

    func testOtherModifiersKeepTheirOwnMeaning() {
        XCTAssertFalse(TerminalKeyboard.sendsNewline(keyCode: 36, flags: [.shift, .command]))
        XCTAssertFalse(TerminalKeyboard.sendsNewline(keyCode: 36, flags: [.shift, .control]))
        XCTAssertFalse(TerminalKeyboard.sendsNewline(keyCode: 36, flags: [.shift, .option]))
    }

    func testOnlyTheReturnKeyCounts() {
        XCTAssertFalse(TerminalKeyboard.sendsNewline(keyCode: 0, flags: [.shift]))
    }

    func testCommandVIsTheClipboardPaste() {
        XCTAssertTrue(TerminalKeyboard.pastesClipboard(keyCode: 9, flags: [.command]))
    }

    func testOtherPasteChordsAreLeftToTheTerminal() {
        XCTAssertFalse(TerminalKeyboard.pastesClipboard(keyCode: 9, flags: []))
        XCTAssertFalse(TerminalKeyboard.pastesClipboard(keyCode: 9, flags: [.command, .shift]))
        XCTAssertFalse(TerminalKeyboard.pastesClipboard(keyCode: 9, flags: [.command, .option]))
        XCTAssertFalse(TerminalKeyboard.pastesClipboard(keyCode: 0, flags: [.command]))
    }
}

final class PageKeyTests: XCTestCase {
    func testPageUpAndDownCarryTheirEscapeSequence() {
        XCTAssertEqual(
            TerminalKeyboard.pageKeyBytes(keyCode: TerminalKeyboard.pageUpKeyCode, flags: []),
            Array("\u{1b}[5~".utf8))
        XCTAssertEqual(
            TerminalKeyboard.pageKeyBytes(keyCode: TerminalKeyboard.pageDownKeyCode, flags: []),
            Array("\u{1b}[6~".utf8))
    }

    func testAModifierLeavesThePageKeyToTheTerminal() {
        for flag in [NSEvent.ModifierFlags.shift, .command, .control, .option] {
            XCTAssertNil(TerminalKeyboard.pageKeyBytes(
                keyCode: TerminalKeyboard.pageUpKeyCode, flags: flag))
        }
    }

    func testAnotherKeyIsNotAPageKey() {
        XCTAssertNil(TerminalKeyboard.pageKeyBytes(keyCode: 36, flags: []))
    }
}
