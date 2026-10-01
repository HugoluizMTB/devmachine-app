import XCTest
@testable import DevmachineCore

final class ScreenColorTests: XCTestCase {
    func testHexIsUppercaseWithAHash() {
        XCTAssertEqual(ScreenColor.hex(red: 1, green: 0.5, blue: 0), "#FF8000")
    }

    func testBlackAndWhite() {
        XCTAssertEqual(ScreenColor.hex(red: 0, green: 0, blue: 0), "#000000")
        XCTAssertEqual(ScreenColor.hex(red: 1, green: 1, blue: 1), "#FFFFFF")
    }

    func testComponentsOutsideTheRangeAreClamped() {
        XCTAssertEqual(ScreenColor.hex(red: 1.2, green: -0.1, blue: 0.2), "#FF0033")
    }

    func testComponentsRoundToTheNearestByte() {
        XCTAssertEqual(ScreenColor.hex(red: 0.1, green: 0.2, blue: 0.3), "#1A334D")
    }

    func testANaNComponentReadsAsZeroInsteadOfCrashing() {
        XCTAssertEqual(ScreenColor.hex(red: .nan, green: 1, blue: 0), "#00FF00")
    }
}
