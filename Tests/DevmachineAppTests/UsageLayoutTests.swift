import XCTest
@testable import DevmachineApp

final class UsageLayoutTests: XCTestCase {
    func testPullRequestsWidthDoesNotGrowWithUsageColumns() {
        XCTAssertEqual(
            MenuBarSizing.width(for: .pullRequests, usageColumns: 2, available: 1_200),
            420)
    }

    func testUsageWidthGrowsFromOneToTwoColumns() {
        XCTAssertEqual(MenuBarSizing.width(for: .usage, usageColumns: 1, available: 1_200), 380)
        XCTAssertEqual(MenuBarSizing.width(for: .usage, usageColumns: 2, available: 1_200), 776)
    }

    func testUsageWidthIsCappedInsideTheVisibleScreen() {
        XCTAssertEqual(MenuBarSizing.width(for: .usage, usageColumns: 2, available: 700), 668)
    }
}
