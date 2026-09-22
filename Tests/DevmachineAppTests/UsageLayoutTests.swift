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
        XCTAssertEqual(MenuBarSizing.columnWidth(panelWidth: 668, usageColumns: 2), 333.5)
    }

    func testFullWidthUsageColumnsRetainTheirPreferredWidth() {
        XCTAssertEqual(MenuBarSizing.columnWidth(panelWidth: 776, usageColumns: 2), 380)
    }

    func testHomeUnmountsWhenAnotherPageCoversTheMainPane() {
        XCTAssertTrue(MainPaneVisibility.showsHome(hasSelection: false, activePage: nil))
        XCTAssertFalse(MainPaneVisibility.showsHome(hasSelection: false, activePage: .stats))
        XCTAssertFalse(MainPaneVisibility.showsHome(hasSelection: true, activePage: nil))
    }
}
