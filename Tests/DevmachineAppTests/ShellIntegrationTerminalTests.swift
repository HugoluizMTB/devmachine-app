import XCTest
import SwiftTerm
@testable import DevmachineCore

final class ShellIntegrationTerminalTests: XCTestCase {
    private final class Replies: TerminalDelegate {
        var sent = ""
        func send(source: Terminal, data: ArraySlice<UInt8>) { sent += String(decoding: data, as: UTF8.self) }
    }

    func testTheResetLeavesTheTerminalReportingNothing() {
        let replies = Replies()
        let terminal = Terminal(delegate: replies)
        terminal.feed(text: "\u{1b}[?1003h\u{1b}[?1006h\u{1b}[?1004h")
        XCTAssertNotEqual(terminal.mouseMode, .off)

        terminal.feed(text: ShellIntegration.resetModes)
        replies.sent = ""
        terminal.feed(text: "\u{1b}[?1004$p\u{1b}[?1006$p")

        XCTAssertEqual(terminal.mouseMode, .off)
        XCTAssertEqual(replies.sent, "\u{1b}[?1004;2$y\u{1b}[?1006;2$y")
    }
}
