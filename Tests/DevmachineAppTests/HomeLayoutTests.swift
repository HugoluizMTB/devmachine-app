import XCTest
@testable import DevmachineApp

final class HomeLayoutTests: XCTestCase {
    func testA1440WindowPutsTheClockLeftOfOneColumnOfMachinesAndUsage() {
        let plan = HomeLayout.plan(width: 1174, harnessCount: 2)

        XCTAssertFalse(plan.stacked)
        XCTAssertEqual(plan.usageColumns, 1)
        XCTAssertEqual(plan.rightWidth, HomeUsageLayout.cardWidth)
        XCTAssertEqual(plan.clockSize, 150)
    }

    func testA1100WindowShrinksTheClockSoItNeverReachesTheRightColumn() {
        let plan = HomeLayout.plan(width: 834, harnessCount: 2)

        XCTAssertFalse(plan.stacked)
        XCTAssertEqual(plan.usageColumns, 1)
        let clockWidth = 834 - HomeLayout.padding * 2 - plan.rightWidth - HomeLayout.gap
        XCTAssertLessThanOrEqual(plan.clockSize * HomeLayout.clockWidthPerPoint, clockWidth)
        XCTAssertLessThan(plan.clockSize, 150)
    }

    func testAVeryWideWindowShowsTwoUsageColumns() {
        let plan = HomeLayout.plan(width: 1900, harnessCount: 2)

        XCTAssertFalse(plan.stacked)
        XCTAssertEqual(plan.usageColumns, 2)
        XCTAssertEqual(plan.rightWidth, HomeUsageLayout.width(for: 2))
    }

    func testANarrowWindowStacksMachinesClockAndUsage() {
        let plan = HomeLayout.plan(width: 640, harnessCount: 2)

        XCTAssertTrue(plan.stacked)
        XCTAssertEqual(plan.usageColumns, 1)
        XCTAssertLessThanOrEqual(plan.clockSize * HomeLayout.clockWidthPerPoint, 640 - HomeLayout.padding * 2)
    }

    func testOneHarnessNeverAsksForTwoColumns() {
        XCTAssertEqual(HomeLayout.plan(width: 2400, harnessCount: 1).usageColumns, 1)
    }

    func testWithoutHarnessesTheRightColumnStillFitsTwoMachineCards() {
        let plan = HomeLayout.plan(width: 1174, harnessCount: 0)

        XCTAssertEqual(plan.usageColumns, 0)
        XCTAssertGreaterThanOrEqual(plan.rightWidth, MachineStatsCard.width * 2 + HomeLayout.cardSpacing)
    }
}
