import XCTest
@testable import DevmachineCore

final class WorkspaceCollapseTests: XCTestCase {
    private let suite = "WorkspaceCollapseTests"

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testToggleAndSetRoundTrip() {
        var collapse = WorkspaceCollapse()
        XCTAssertFalse(collapse.isCollapsed("acme-devmachine"))
        collapse.toggle("acme-devmachine")
        XCTAssertTrue(collapse.isCollapsed("acme-devmachine"))
        collapse.toggle("acme-devmachine")
        XCTAssertFalse(collapse.isCollapsed("acme-devmachine"))
        collapse.set("beta-devmachine", collapsed: true)
        collapse.set("beta-devmachine", collapsed: true)
        XCTAssertEqual(collapse.collapsed, ["beta-devmachine"])
        collapse.set("beta-devmachine", collapsed: false)
        XCTAssertEqual(collapse.collapsed, [])
    }

    func testLoadAndSaveUseAStringArray() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(WorkspaceCollapse.load(defaults), WorkspaceCollapse())
        var collapse = WorkspaceCollapse()
        collapse.toggle("acme-devmachine")
        collapse.toggle("local")
        collapse.save(defaults)
        XCTAssertEqual(Set(defaults.stringArray(forKey: WorkspaceCollapse.defaultsKey) ?? []), ["acme-devmachine", "local"])
        XCTAssertEqual(WorkspaceCollapse.load(defaults), collapse)
    }

    func testOnlyTheToggledWorkspaceIsCollapsed() {
        var collapse = WorkspaceCollapse()
        collapse.toggle("acme-devmachine")
        XCTAssertTrue(collapse.isCollapsed("acme-devmachine"))
        XCTAssertFalse(collapse.isCollapsed("beta-devmachine"))
    }

    func testCountLabel() {
        XCTAssertEqual(WorkspaceCollapse.countLabel(0), "")
        XCTAssertEqual(WorkspaceCollapse.countLabel(4), "4")
        XCTAssertEqual(WorkspaceCollapse.countLabel(1234), "1234")
    }
}
