import XCTest
@testable import HarnessUsageKit

final class UsageDailyChartTests: XCTestCase {
    func testLongHistoriesShowAtMostSevenEvenlySpacedAxisLabels() {
        let days = (1...27).map {
            DayTokens(date: String(format: "2026-09-%02d", $0), tokens: Int64($0))
        }

        XCTAssertEqual(
            UsageDailyChartLabels.visibleDates(in: days),
            [
                "2026-09-01", "2026-09-05", "2026-09-10", "2026-09-14",
                "2026-09-18", "2026-09-23", "2026-09-27"
            ])
    }

    func testShortHistoriesKeepEveryAxisLabel() {
        let days = [
            DayTokens(date: "2026-09-21", tokens: 1),
            DayTokens(date: "2026-09-22", tokens: 2),
            DayTokens(date: "2026-09-23", tokens: 3)
        ]

        XCTAssertEqual(
            UsageDailyChartLabels.visibleDates(in: days),
            ["2026-09-21", "2026-09-22", "2026-09-23"])
    }
}
