import XCTest
@testable import DevmachineApp

final class UsageLayoutTests: XCTestCase {
    func testEveryMenuBarTabKeepsTheSameWideWidth() {
        XCTAssertEqual(
            MenuBarSizing.width(for: .pullRequests, usageColumns: 1, available: 1_200),
            776)
        XCTAssertEqual(MenuBarSizing.width(for: .usage, usageColumns: 1, available: 1_200), 776)
        XCTAssertEqual(MenuBarSizing.width(for: .usage, usageColumns: 2, available: 1_200), 776)
    }

    func testEveryMenuBarTabKeepsTheSameHeight() {
        XCTAssertEqual(MenuBarSizing.height(for: .pullRequests), 640)
        XCTAssertEqual(MenuBarSizing.height(for: .usage), 640)
    }

    func testUsageWidthIsCappedInsideTheVisibleScreen() {
        XCTAssertEqual(MenuBarSizing.width(for: .usage, usageColumns: 2, available: 700), 668)
        XCTAssertEqual(MenuBarSizing.columnWidth(panelWidth: 668, usageColumns: 2), 333.5)
    }

    func testFullWidthUsageColumnsRetainTheirPreferredWidth() {
        XCTAssertEqual(MenuBarSizing.columnWidth(panelWidth: 776, usageColumns: 1), 776)
        XCTAssertEqual(MenuBarSizing.columnWidth(panelWidth: 776, usageColumns: 2), 380)
    }

    func testHomeUnmountsWhenAnotherPageCoversTheMainPane() {
        XCTAssertTrue(MainPaneVisibility.showsHome(hasSelection: false, activePage: nil))
        XCTAssertFalse(MainPaneVisibility.showsHome(hasSelection: false, activePage: .stats))
        XCTAssertFalse(MainPaneVisibility.showsHome(hasSelection: true, activePage: nil))
    }
}
