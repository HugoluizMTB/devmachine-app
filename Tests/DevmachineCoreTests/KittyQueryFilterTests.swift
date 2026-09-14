import XCTest
@testable import DevmachineCore

final class KittyQueryFilterTests: XCTestCase {
    private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    func testDropsTheQueryAnswer() {
        XCTAssertEqual(KittyQueryFilter.strip(bytes("\u{1B}[?0u")), [])
        XCTAssertEqual(KittyQueryFilter.strip(bytes("\u{1B}[?31u")), [])
    }

    func testKeepsSurroundingBytes() {
        let input = bytes("abc\u{1B}[?0u\u{1B}[?1;2cxyz")
        XCTAssertEqual(KittyQueryFilter.strip(input), bytes("abc\u{1B}[?1;2cxyz"))
    }

    func testKeepsKittyEncodedKeysAndOtherCSI() {
        for s in ["\u{1B}[13u", "\u{1B}[97;5u", "\u{1B}[?1049h", "\u{1B}[?u", "é\r"] {
            XCTAssertEqual(KittyQueryFilter.strip(bytes(s)), bytes(s), s)
        }
    }

    func testTruncatedSequenceIsLeftAlone() {
        XCTAssertEqual(KittyQueryFilter.strip(bytes("\u{1B}[?3")), bytes("\u{1B}[?3"))
    }
}
