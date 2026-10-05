import XCTest
@testable import DevmachineCore

final class SidebarOrderTests: XCTestCase {
    private let live = ["acme", "initech", "globex", "local"]

    func testNothingSavedKeepsTheLiveOrder() {
        XCTAssertEqual(SidebarOrder().workspaces(live), live)
    }

    func testSavedWorkspacesComeFirstInTheSavedOrder() {
        let order = SidebarOrder(workspaces: ["local", "globex"])
        XCTAssertEqual(order.workspaces(live), ["local", "globex", "acme", "initech"])
    }

    func testASavedWorkspaceThatIsNotLiveIsLeftOut() {
        let order = SidebarOrder(workspaces: ["gone", "globex"])
        XCTAssertEqual(order.workspaces(live), ["globex", "acme", "initech", "local"])
    }

    func testMovingDownLandsAfterTheTarget() {
        var order = SidebarOrder()
        order.moveWorkspace("acme", onto: "globex", live: live)
        XCTAssertEqual(order.workspaces(live), ["initech", "globex", "acme", "local"])
    }

    func testMovingUpLandsBeforeTheTarget() {
        var order = SidebarOrder()
        order.moveWorkspace("local", onto: "initech", live: live)
        XCTAssertEqual(order.workspaces(live), ["acme", "local", "initech", "globex"])
    }

    func testMovingOntoItselfChangesNothing() {
        var order = SidebarOrder()
        order.moveWorkspace("acme", onto: "acme", live: live)
        XCTAssertEqual(order, SidebarOrder())
    }

    func testMovingSomethingNotLiveChangesNothing() {
        var order = SidebarOrder()
        order.moveWorkspace("gone", onto: "acme", live: live)
        XCTAssertEqual(order, SidebarOrder())
    }

    func testANewWorkspaceGoesToTheEnd() {
        var order = SidebarOrder()
        order.moveWorkspace("local", onto: "acme", live: live)
        XCTAssertEqual(order.workspaces(live + ["umbrella"]),
                       ["local", "acme", "initech", "globex", "umbrella"])
    }

    func testSessionsAreOrderedPerWorkspace() {
        var order = SidebarOrder()
        order.moveSession("c", onto: "a", in: "acme", live: ["a", "b", "c"])
        XCTAssertEqual(order.sessions(["a", "b", "c"], in: "acme"), ["c", "a", "b"])
        XCTAssertEqual(order.sessions(["a", "b", "c"], in: "globex"), ["a", "b", "c"])
    }

    func testANewSessionGoesToTheEnd() {
        var order = SidebarOrder()
        order.moveSession("b", onto: "a", in: "acme", live: ["a", "b"])
        XCTAssertEqual(order.sessions(["new", "a", "b"], in: "acme"), ["b", "a", "new"])
    }

    func testRemovingAWorkspaceForgetsItAndItsSessions() {
        var order = SidebarOrder()
        order.moveWorkspace("globex", onto: "acme", live: live)
        order.moveSession("b", onto: "a", in: "globex", live: ["a", "b"])
        order.moveSession("b", onto: "a", in: "acme", live: ["a", "b"])
        order.removeWorkspace("GLOBEX")
        XCTAssertFalse(order.savedWorkspaces.contains("globex"))
        XCTAssertNil(order.savedSessions["globex"])
        XCTAssertEqual(order.savedSessions["acme"], ["b", "a"])
    }

    func testKeepingWorkspacesForgetsTheOthers() {
        var order = SidebarOrder()
        order.moveWorkspace("globex", onto: "acme", live: live)
        order.moveSession("b", onto: "a", in: "initech", live: ["a", "b"])
        order.keepWorkspaces(["ACME", "globex", "local"])
        XCTAssertEqual(order.savedWorkspaces, ["globex", "acme", "local"])
        XCTAssertNil(order.savedSessions["initech"])
    }

    func testRemovingASessionForgetsOnlyIt() {
        var order = SidebarOrder()
        order.moveSession("c", onto: "a", in: "acme", live: ["a", "b", "c"])
        order.removeSession("a", in: "acme")
        XCTAssertEqual(order.savedSessions["acme"], ["c", "b"])
    }

    func testKeepingSessionsForgetsTheMissingOnes() {
        var order = SidebarOrder()
        order.moveSession("c", onto: "a", in: "acme", live: ["a", "b", "c"])
        order.keepSessions(["a", "c"], in: "acme")
        XCTAssertEqual(order.savedSessions["acme"], ["c", "a"])
    }

    func testKeepingNoSessionsDropsTheWorkspaceKey() {
        var order = SidebarOrder()
        order.moveSession("b", onto: "a", in: "acme", live: ["a", "b"])
        order.keepSessions([], in: "acme")
        XCTAssertNil(order.savedSessions["acme"])
    }

    func testRenamingASessionKeepsItsPlace() {
        var order = SidebarOrder()
        order.moveSession("c", onto: "a", in: "acme", live: ["a", "b", "c"])
        order.renameSession("c", to: "z", in: "acme")
        XCTAssertEqual(order.sessions(["a", "b", "z"], in: "acme"), ["z", "a", "b"])
    }

    func testRoundTripsThroughJSON() throws {
        var order = SidebarOrder()
        order.moveWorkspace("local", onto: "acme", live: live)
        order.moveSession("b", onto: "a", in: "acme", live: ["a", "b"])
        let data = try JSONEncoder().encode(order)
        XCTAssertEqual(try JSONDecoder().decode(SidebarOrder.self, from: data), order)
    }
}

final class SidebarDropTests: XCTestCase {
    func testAWorkspaceDropsOnAnyPartOfAnotherWorkspace() {
        XCTAssertEqual(
            SidebarDrop.action(dragging: .workspace("acme"), over: .session("x", in: "globex")),
            .moveWorkspace("acme", onto: "globex"))
        XCTAssertEqual(
            SidebarDrop.action(dragging: .workspace("acme"), over: .workspace("local")),
            .moveWorkspace("acme", onto: "local"))
    }

    func testASessionMovesInsideItsWorkspace() {
        XCTAssertEqual(
            SidebarDrop.action(dragging: .session("a", in: "acme"), over: .session("b", in: "acme")),
            .moveSession("a", onto: "b", in: "acme"))
    }

    func testASessionOverItsOwnHeaderStaysPut() {
        XCTAssertEqual(
            SidebarDrop.action(dragging: .session("a", in: "acme"), over: .workspace("acme")),
            .stay)
    }

    func testASessionNeverLeavesItsWorkspace() {
        XCTAssertEqual(
            SidebarDrop.action(dragging: .session("a", in: "acme"), over: .session("b", in: "local")),
            .refuse)
        XCTAssertEqual(
            SidebarDrop.action(dragging: .session("a", in: "local"), over: .workspace("acme")),
            .refuse)
    }

    func testTheDragTokenRoundTrips() {
        for item in [SidebarDragItem.workspace("acme"), .session("a-1", in: "local")] {
            XCTAssertEqual(SidebarDragItem(token: item.token), item)
        }
        XCTAssertNil(SidebarDragItem(token: "something else"))
    }
}
