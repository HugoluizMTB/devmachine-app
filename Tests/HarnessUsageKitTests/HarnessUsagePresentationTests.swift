import XCTest
@testable import HarnessUsageKit

final class HarnessUsagePresentationTests: XCTestCase {
    func testHeaderOmitsParenthesesWhenThereIsNoPlan() {
        let state = HarnessUsageState(harnessID: "codex", snapshot: .init())
        let presentation = HarnessUsagePresentation(title: "Codex Usage", state: state)

        XCTAssertEqual(presentation.headerTitle, "Codex Usage")
    }

    func testOptionalSectionsReflectTheSnapshot() {
        let stats = UsageStats(
            dailyTotals: [], modelTotals: [], todayTokens: 0, mostUsedModel: nil)
        let metric = UsageSummaryMetric(id: "streak", label: "Streak", value: "3 days")
        let state = HarnessUsageState(
            harnessID: "codex",
            snapshot: .init(planName: "Pro", blocks: [], stats: stats, summaryMetrics: [metric]))
        let presentation = HarnessUsagePresentation(title: "Codex Usage", state: state)

        XCTAssertEqual(presentation.headerTitle, "Codex Usage (Pro)")
        XCTAssertFalse(presentation.showsModelBreakdown)
        XCTAssertEqual(presentation.summaryMetrics, [metric])
    }

    func testErrorCopyNamesOnlyThePresentedProvider() {
        let state = HarnessUsageState(harnessID: "tool", errorText: "offline")
        let presentation = HarnessUsagePresentation(title: "Tool Usage", state: state)

        XCTAssertEqual(presentation.error?.title, "Tool usage isn't available")
        XCTAssertEqual(presentation.error?.details, "offline")
    }

    func testSizingMetadataIsStable() {
        XCTAssertEqual(UsagePanelMetrics.columnWidth, 380)
        XCTAssertEqual(UsagePanelMetrics.contentSpacing, 16)
    }
}
