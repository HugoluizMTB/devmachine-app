import XCTest
@testable import DevmachineApp

final class DMFontTests: XCTestCase {
    override func tearDown() {
        DMFont.scale = 1
        super.tearDown()
    }

    func testScaleOneLeavesASizeAlone() {
        DMFont.scale = 1
        XCTAssertEqual(DMFont.size(11), 11)
    }

    func testEverySizeGrowsTogether() {
        DMFont.scale = 1.5
        XCTAssertEqual(DMFont.size(10), 15)
        XCTAssertEqual(DMFont.size(12), 18)
    }

    func testSizesLandOnHalfPoints() {
        DMFont.scale = 1.05
        XCTAssertEqual(DMFont.size(11), 11.5)
    }

    func testASizeNeverReachesZero() {
        DMFont.scale = 0.01
        XCTAssertEqual(DMFont.size(9), 1)
    }
}
