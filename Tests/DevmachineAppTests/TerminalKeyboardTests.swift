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
}
