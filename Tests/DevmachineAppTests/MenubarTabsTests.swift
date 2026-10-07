import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

final class MenubarTabsTests: XCTestCase {
    private let panel = DefaultStackBoard.make(surface: "menubar-panel")

    private func tabs(_ board: StackBoard, approvals: Bool = false) -> [MenubarTab] {
        MenubarTabs.make(
            board: board, resolve: { StackResolution.resolve($0, on: board, catalog: nil) }, catalog: nil,
            hasApprovals: approvals)
    }

    func testTheDefaultPanelHasTodaysTwoTabs() {
        let made = tabs(panel)
        XCTAssertEqual(made.map(\.title), MenuBarTab.allCases.map(\.title))
        XCTAssertEqual(made.map(\.systemImage), MenuBarTab.allCases.map(\.systemImage))
        XCTAssertEqual(made.map(\.id), [.entry("pull-requests-panel"), .entry("usage-panel")])
    }

    func testApprovalsComeFirstAndOpenFirst() {
        let made = tabs(panel, approvals: true)
        XCTAssertEqual(made.first?.id, .approvals)
        XCTAssertEqual(made.first?.title, "Approvals")
        XCTAssertEqual(MenubarTabs.opening(made, preferred: "usage-panel"), .approvals)
    }

    func testOpeningPrefersTheAskedTabWhenItIsThere() {
        XCTAssertEqual(MenubarTabs.opening(tabs(panel), preferred: "usage-panel"), .entry("usage-panel"))
        XCTAssertEqual(MenubarTabs.opening(tabs(panel), preferred: "gone"), .entry("pull-requests-panel"))
        XCTAssertNil(MenubarTabs.opening([], preferred: nil))
    }

    func testARemovedTabFallsBackToTheFirstWidgetTab() {
        var board = panel
        board.remove("usage-panel")
        XCTAssertEqual(MenubarTabs.keeping(.entry("usage-panel"), in: tabs(board)), .entry("pull-requests-panel"))
        XCTAssertEqual(MenubarTabs.keeping(.approvals, in: tabs(board)), .entry("pull-requests-panel"))
        XCTAssertEqual(MenubarTabs.keeping(.entry("pull-requests-panel"), in: tabs(board)), .entry("pull-requests-panel"))
    }

    func testAnotherWidgetsTabUsesItsTitleAndNoIcon() throws {
        let text = "format: 1\nsurface: menubar-panel\nwidgets:\n  - id: log\n    title: Deploy log\n    source: {kind: url, url: https://example.com, every: 60s}\n    view: {kind: status}\n"
        let board = try BoardCodec.decodeStack(text)
        XCTAssertEqual(tabs(board).map(\.title), ["Deploy log"])
        XCTAssertEqual(tabs(board).map(\.systemImage), [nil])
    }

    func testEditingShowsNoTabSoNoTabRuns() {
        XCTAssertNil(MenubarTabs.shownEntry(.entry("usage-panel"), editing: true))
        XCTAssertEqual(MenubarTabs.shownEntry(.entry("usage-panel"), editing: false), "usage-panel")
        XCTAssertNil(MenubarTabs.shownEntry(.approvals, editing: false))
    }

    func testTheWindowOpensAndClosesThePopoverOnceWhateverSignalComesFirst() {
        XCTAssertEqual(MenubarPanelPresence.change(after: .appeared, isOpen: false), true)
        XCTAssertEqual(MenubarPanelPresence.change(after: .becameKey, isOpen: false), true)
        XCTAssertNil(MenubarPanelPresence.change(after: .becameKey, isOpen: true))
        XCTAssertNil(MenubarPanelPresence.change(after: .appeared, isOpen: true))
        XCTAssertEqual(MenubarPanelPresence.change(after: .disappeared, isOpen: true), false)
        XCTAssertEqual(MenubarPanelPresence.change(after: .resignedKey(stillVisible: false), isOpen: true), false)
        XCTAssertNil(MenubarPanelPresence.change(after: .resignedKey(stillVisible: true), isOpen: true))
        XCTAssertNil(MenubarPanelPresence.change(after: .disappeared, isOpen: false))
        XCTAssertNil(MenubarPanelPresence.change(after: .resignedKey(stillVisible: false), isOpen: false))
    }

    func testEntryIDs() {
        XCTAssertEqual(MenubarTabs.entryID(.entry("a")), "a")
        XCTAssertNil(MenubarTabs.entryID(.approvals))
        XCTAssertEqual(MenuBarTab.pullRequests.defaultEntryID, "pull-requests-panel")
        XCTAssertEqual(MenuBarTab(viewKind: "app.usage-panel"), .usage)
        XCTAssertNil(MenuBarTab(viewKind: "text"))
    }
}
