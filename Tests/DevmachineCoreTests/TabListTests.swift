import XCTest
@testable import DevmachineCore

final class TabListTests: XCTestCase {
    func testOpenAppendsOnceAndKeepsOrder() {
        var tabs = TabList<String>()
        tabs.open("a")
        tabs.open("b")
        tabs.open("a")
        tabs.open("c")
        XCTAssertEqual(tabs.items, ["a", "b", "c"])
        XCTAssertTrue(tabs.contains("b"))
        XCTAssertFalse(tabs.contains("d"))
    }

    func testClosingTheSelectedItemPicksTheNeighbour() {
        var tabs = TabList(["a", "b", "c"])
        XCTAssertEqual(tabs.close("b", selected: "b"), "c")
        XCTAssertEqual(tabs.items, ["a", "c"])
        XCTAssertEqual(tabs.close("c", selected: "c"), "a")
        XCTAssertNil(tabs.close("a", selected: "a"))
        XCTAssertEqual(tabs.items, [])
    }

    func testClosingAnotherItemKeepsTheSelection() {
        var tabs = TabList(["a", "b", "c"])
        XCTAssertEqual(tabs.close("a", selected: "c"), "c")
        XCTAssertEqual(tabs.close("zzz", selected: "c"), "c")
        XCTAssertEqual(tabs.close("b", selected: nil), nil)
        XCTAssertEqual(tabs.items, ["c"])
    }

    func testReplaceKeepsThePlace() {
        var tabs = TabList(["a", "b", "c"])
        tabs.replace("b", with: "B")
        XCTAssertEqual(tabs.items, ["a", "B", "c"])
        tabs.replace("B", with: "c")
        XCTAssertEqual(tabs.items, ["a", "c"])
        tabs.replace("missing", with: "x")
        XCTAssertEqual(tabs.items, ["a", "c"])
    }

    func testRemoveAllWhere() {
        var tabs = TabList(["a1", "b1", "a2"])
        tabs.removeAll { $0.hasPrefix("a") }
        XCTAssertEqual(tabs.items, ["b1"])
    }
}
