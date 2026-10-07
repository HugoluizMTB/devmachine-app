import XCTest
@testable import DevmachineCore

final class StackBoardTests: XCTestCase {
    private func board(_ ids: [String]) -> StackBoard {
        StackBoard(surface: "context-sidebar", entries: ids.map { StackEntry(id: $0, type: "devmachine-app/\($0)") })
    }

    private func ids(_ board: StackBoard) -> [String] { board.entries.map(\.id) }

    func testInsertGoesAtTheEndOrBesideAnAnchor() {
        var stack = board(["a", "c"])
        XCTAssertTrue(stack.insert(StackEntry(id: "d", type: "x/d"), at: .end))
        XCTAssertTrue(stack.insert(StackEntry(id: "b", type: "x/b"), at: .after("a")))
        XCTAssertTrue(stack.insert(StackEntry(id: "z", type: "x/z"), at: .before("a")))
        XCTAssertEqual(ids(stack), ["z", "a", "b", "c", "d"])
    }

    func testInsertRefusesAMissingAnchorOrATakenID() {
        var stack = board(["a"])
        XCTAssertFalse(stack.insert(StackEntry(id: "b", type: "x/b"), at: .after("ghost")))
        XCTAssertFalse(stack.insert(StackEntry(id: "a", type: "x/a"), at: .end))
        XCTAssertEqual(ids(stack), ["a"])
    }

    func testMoveBeforeAndAfter() {
        var stack = board(["a", "b", "c", "d"])
        XCTAssertTrue(stack.move("d", to: .before("b")))
        XCTAssertEqual(ids(stack), ["a", "d", "b", "c"])
        XCTAssertTrue(stack.move("a", to: .after("c")))
        XCTAssertEqual(ids(stack), ["d", "b", "c", "a"])
        XCTAssertTrue(stack.move("b", to: .end))
        XCTAssertEqual(ids(stack), ["d", "c", "a", "b"])
    }

    func testMoveRefusesItselfAsAnchorAndUnknownIDs() {
        var stack = board(["a", "b"])
        XCTAssertFalse(stack.move("a", to: .before("a")))
        XCTAssertFalse(stack.move("ghost", to: .end))
        XCTAssertFalse(stack.move("a", to: .after("ghost")))
        XCTAssertEqual(ids(stack), ["a", "b"])
    }

    func testMoveToIndexIsWhereTheEntryEndsUp() {
        var stack = board(["a", "b", "c", "d"])
        XCTAssertTrue(stack.move("a", toIndex: 2))
        XCTAssertEqual(ids(stack), ["b", "c", "a", "d"])
        XCTAssertTrue(stack.move("d", toIndex: 0))
        XCTAssertEqual(ids(stack), ["d", "b", "c", "a"])
        XCTAssertTrue(stack.move("b", toIndex: 99))
        XCTAssertEqual(ids(stack), ["d", "c", "a", "b"])
        XCTAssertFalse(stack.move("b", toIndex: 3))
    }

    func testUpAndDownStopAtTheEnds() {
        var stack = board(["a", "b", "c"])
        XCTAssertFalse(stack.moveUp("a"))
        XCTAssertFalse(stack.moveDown("c"))
        XCTAssertTrue(stack.moveDown("a"))
        XCTAssertTrue(stack.moveUp("c"))
        XCTAssertEqual(ids(stack), ["b", "c", "a"])
    }

    func testRemoveCollapseAndSize() {
        var stack = board(["a", "b"])
        XCTAssertTrue(stack.setCollapsed("a", true))
        XCTAssertTrue(stack.setSize("b", .preset("large")))
        XCTAssertFalse(stack.setCollapsed("a", true))
        XCTAssertFalse(stack.setSize("ghost", .auto))
        XCTAssertEqual(stack.entries[0].collapsed, true)
        XCTAssertEqual(stack.entries[1].size, .preset("large"))
        XCTAssertTrue(stack.remove("a"))
        XCTAssertFalse(stack.remove("a"))
        XCTAssertEqual(ids(stack), ["b"])
    }

    func testUniqueIDsFollowTheBoardRule() {
        let stack = board(["workspaces", "links"])
        XCTAssertEqual(stack.uniqueID(base: "workspaces"), "workspaces-2")
        XCTAssertEqual(stack.uniqueID(base: "Disk Usage"), "disk-usage")
        XCTAssertEqual(stack.uniqueID(base: "!!"), "widget")
        XCTAssertEqual(Board(surface: "home", widgets: []).uniqueID(base: "Disk Usage"), "disk-usage")
    }

    func testStackSizeReadsPresetsAndAuto() {
        XCTAssertEqual(StackSize(text: "auto"), .auto)
        XCTAssertEqual(StackSize(text: "tall"), .preset("tall"))
        XCTAssertNil(StackSize(text: "huge"))
        XCTAssertEqual(StackSize.preset("wide").text, "wide")
        XCTAssertEqual(StackSize.auto.presetName, nil)
    }

    func testTheBoardWidgetCarriesWhatTheResolverReads() {
        let entry = StackEntry(id: "disk", type: "acme/disk", with: ["path": .string("/")], size: .preset("large"))
        let widget = entry.boardWidget
        XCTAssertEqual(widget.id, "disk")
        XCTAssertEqual(widget.type, "acme/disk")
        XCTAssertEqual(widget.with, ["path": .string("/")])
        XCTAssertEqual(widget.size, "large")
        XCTAssertEqual(StackEntry(id: "x", type: "a/x", size: .auto).boardWidget.size, BoardWidget.customSize)
    }

    func testTheDefaultBoardsAreTodaysSidebarAndContextTab() {
        XCTAssertEqual(DefaultStackBoard.make(surface: "sidebar"), StackBoard(surface: "sidebar", entries: [
            StackEntry(id: "workspaces", type: "devmachine-app/workspaces", size: .auto),
        ]))
        let context = DefaultStackBoard.make(surface: "context-sidebar")
        XCTAssertEqual(context.surface, "context-sidebar")
        XCTAssertEqual(ids(context), [
            "shortcuts", "publish-port", "monitors", "shells", "sub-agents", "todo", "pull-requests", "links",
        ])
        XCTAssertEqual(Set(context.entries.map(\.size)), [.auto])
        XCTAssertEqual(context.entries.map(\.type), context.entries.map { "devmachine-app/\($0.id)" })
        XCTAssertEqual(DefaultStackBoard.make(surface: "home").entries, [])
    }
}
