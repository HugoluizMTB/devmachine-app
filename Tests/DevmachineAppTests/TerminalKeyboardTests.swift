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
}
