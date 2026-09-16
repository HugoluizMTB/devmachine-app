import XCTest
@testable import DevmachineCore

final class TerminalSizeGuardTests: XCTestCase {
    func testARealWindowIsUsable() {
        XCTAssertTrue(TerminalSizeGuard.isUsable(cols: 222, rows: 72))
        XCTAssertTrue(TerminalSizeGuard.isUsable(cols: 80, rows: 24))
    }

    func testAMeasurementInProgressIsNot() {
        // Sizes seen while SwiftUI settles a pane.
        XCTAssertFalse(TerminalSizeGuard.isUsable(cols: 2, rows: 1))
        XCTAssertFalse(TerminalSizeGuard.isUsable(cols: 38, rows: 14))
        XCTAssertFalse(TerminalSizeGuard.isUsable(cols: 50, rows: 8))
    }

    func testTheEdgeOfTheRuleIsUsable() {
        XCTAssertTrue(TerminalSizeGuard.isUsable(cols: 40, rows: 10))
        XCTAssertFalse(TerminalSizeGuard.isUsable(cols: 39, rows: 10))
        XCTAssertFalse(TerminalSizeGuard.isUsable(cols: 40, rows: 9))
    }
}
