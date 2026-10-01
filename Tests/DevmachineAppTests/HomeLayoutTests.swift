import XCTest
@testable import DevmachineApp

final class HomeLayoutTests: XCTestCase {
    func testALargerTextSizeKeepsTwoMachineCardsSideBySide() {
        let m = DMMetrics(scale: 1.3)
        let plan = HomeLayout.plan(width: 1500, harnessCount: 1, metrics: m)

        XCTAssertFalse(plan.stacked)
        let twoCards = m.pt(MachineStatsCard.width) * 2 + m.pt(HomeLayout.cardSpacing)
        XCTAssertGreaterThanOrEqual(plan.cardsWidth, twoCards)
    }

    func testA1440WindowPutsMachinesAndUsageInALeftColumnBesideTheClock() {
        let plan = HomeLayout.plan(width: 1174, harnessCount: 2)

        XCTAssertFalse(plan.stacked)
        XCTAssertEqual(plan.cardsEdge, .leading)
        XCTAssertEqual(plan.usageColumns, 1)
        XCTAssertEqual(plan.cardsWidth, HomeUsageLayout.cardWidth)
        XCTAssertEqual(plan.clockSize, 150)
    }

    func testA1100WindowShrinksTheClockSoItNeverReachesTheCardColumn() {
        let plan = HomeLayout.plan(width: 834, harnessCount: 2)

        XCTAssertFalse(plan.stacked)
        XCTAssertEqual(plan.cardsEdge, .leading)
        XCTAssertEqual(plan.usageColumns, 1)
        let clockWidth = 834 - HomeLayout.padding * 2 - plan.cardsWidth - HomeLayout.gap
        XCTAssertLessThanOrEqual(plan.clockSize * HomeLayout.clockWidthPerPoint, clockWidth)
        XCTAssertLessThan(plan.clockSize, 150)
    }

    func testAVeryWideWindowShowsTwoUsageColumns() {
        let plan = HomeLayout.plan(width: 1900, harnessCount: 2)

        XCTAssertFalse(plan.stacked)
        XCTAssertEqual(plan.usageColumns, 2)
        XCTAssertEqual(plan.cardsWidth, HomeUsageLayout.width(for: 2))
    }

    func testANarrowWindowStacksMachinesClockAndUsageFromTheLeft() {
        let plan = HomeLayout.plan(width: 640, harnessCount: 2)

        XCTAssertTrue(plan.stacked)
        XCTAssertEqual(plan.cardsEdge, .leading)
        XCTAssertEqual(plan.usageColumns, 1)
        XCTAssertLessThanOrEqual(plan.clockSize * HomeLayout.clockWidthPerPoint, 640 - HomeLayout.padding * 2)
    }

    func testOneHarnessNeverAsksForTwoColumns() {
        XCTAssertEqual(HomeLayout.plan(width: 2400, harnessCount: 1).usageColumns, 1)
    }

    func testWithoutHarnessesTheCardColumnStillFitsTwoMachineCards() {
        let plan = HomeLayout.plan(width: 1174, harnessCount: 0)

        XCTAssertEqual(plan.usageColumns, 0)
        XCTAssertGreaterThanOrEqual(plan.cardsWidth, MachineStatsCard.width * 2 + HomeLayout.cardSpacing)
    }
}
