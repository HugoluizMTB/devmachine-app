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

    func testAWideHomeCentresTheClockInTheWholeHome() {
        for width: CGFloat in [1280, 1488, 1728, 2000] {
            let plan = HomeLayout.plan(width: width, harnessCount: 1)
            XCTAssertTrue(plan.clockCentredInHome, "\(width)")
            XCTAssertFalse(plan.stacked)
        }
    }

    func testTheCentredClockClearsTheCardsColumnByTheGap() {
        for width: CGFloat in stride(from: 700, through: 2400, by: 10) {
            for harnesses in 0...2 {
                let plan = HomeLayout.plan(width: width, harnessCount: harnesses)
                guard plan.clockCentredInHome else { continue }
                let clockLeft = width / 2 - plan.clockSize * HomeLayout.clockWidthPerPoint / 2
                XCTAssertGreaterThanOrEqual(
                    clockLeft, HomeLayout.padding + plan.cardsWidth + HomeLayout.gap, "\(width), \(harnesses)")
            }
        }
    }

    func testANarrowerHomeKeepsTheClockInTheColumnBesideTheCards() {
        let plan = HomeLayout.plan(width: 1040, harnessCount: 1)
        XCTAssertFalse(plan.stacked)
        XCTAssertFalse(plan.clockCentredInHome, "centred, it would come closer than the gap to the cards")
    }

    func testTheSidebarOnlyChangesHomesWidth() {
        let collapsed = HomeLayout.plan(width: 1280, harnessCount: 1)
        let shown = HomeLayout.plan(width: 1280 - 240, harnessCount: 1)
        XCTAssertTrue(collapsed.clockCentredInHome)
        XCTAssertFalse(shown.clockCentredInHome)
        XCTAssertTrue(HomeLayout.plan(width: 1728, harnessCount: 1).clockCentredInHome)
        XCTAssertTrue(HomeLayout.plan(width: 1728 - 240, harnessCount: 1).clockCentredInHome)
    }

    func testAStackedHomeNeverMovesTheClockOutOfItsColumn() {
        XCTAssertFalse(HomeLayout.plan(width: 640, harnessCount: 2).clockCentredInHome)
    }

    func testALargerTextSizeStillKeepsTheGapToTheCards() {
        let m = DMMetrics(scale: 1.6)
        for width: CGFloat in [1280, 1728, 2400] {
            let plan = HomeLayout.plan(width: width, harnessCount: 1, metrics: m)
            guard plan.clockCentredInHome else { continue }
            let clockLeft = width / 2 - m.pt(plan.clockSize) * HomeLayout.clockWidthPerPoint / 2
            XCTAssertGreaterThanOrEqual(clockLeft, m.pt(HomeLayout.padding) + plan.cardsWidth + m.pt(HomeLayout.gap))
        }
    }
}
