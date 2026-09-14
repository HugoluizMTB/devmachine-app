import XCTest
@testable import DevmachineCore

final class TerminalReplyFilterTests: XCTestCase {
    private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    func testDropsTheKittyQueryAnswer() {
        XCTAssertEqual(TerminalReplyFilter.strip(bytes("\u{1B}[?0u")), [])
        XCTAssertEqual(TerminalReplyFilter.strip(bytes("\u{1B}[?31u")), [])
    }

    func testDropsTheXTVersionReply() {
        XCTAssertEqual(TerminalReplyFilter.strip(bytes("\u{1B}P>|XTerm(1.20.0)\u{1B}\\")), [])
        XCTAssertEqual(TerminalReplyFilter.strip(bytes("a\u{1B}P>|SwiftTerm main\u{1B}\\b")), bytes("ab"))
    }

    func testKeepsSurroundingBytes() {
        let input = bytes("abc\u{1B}[?0u\u{1B}[?1;2cxyz")
        XCTAssertEqual(TerminalReplyFilter.strip(input), bytes("abc\u{1B}[?1;2cxyz"))
    }

    func testKeepsKittyEncodedKeysAndOtherCSI() {
        for s in ["\u{1B}[13u", "\u{1B}[97;5u", "\u{1B}[?1049h", "\u{1B}[?u", "\u{1B}P+q544e\u{1B}\\", "é\r"] {
            XCTAssertEqual(TerminalReplyFilter.strip(bytes(s)), bytes(s), s)
        }
    }

    func testTruncatedSequencesAreLeftAlone() {
        XCTAssertEqual(TerminalReplyFilter.strip(bytes("\u{1B}[?3")), bytes("\u{1B}[?3"))
        XCTAssertEqual(TerminalReplyFilter.strip(bytes("\u{1B}P>|XTerm(")), bytes("\u{1B}P>|XTerm("))
    }
}
