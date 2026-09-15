import XCTest
@testable import DevmachineApp

final class DMProgressBarTests: XCTestCase {
    func testFractionIsTheShareDone() {
        XCTAssertEqual(DMProgressBar.fraction(done: 1, total: 4), 0.25)
        XCTAssertEqual(DMProgressBar.fraction(done: 4, total: 4), 1)
    }

    func testAnEmptyTotalReadsAsEmpty() {
        XCTAssertEqual(DMProgressBar.fraction(done: 3, total: 0), 0)
        XCTAssertEqual(DMProgressBar.fraction(done: 3, total: -1), 0)
    }

    func testTheBarNeverOverflowsOrGoesNegative() {
        XCTAssertEqual(DMProgressBar.fraction(done: 9, total: 4), 1)
        XCTAssertEqual(DMProgressBar.fraction(done: -5, total: 4), 0)
    }
}
