import XCTest
@testable import DevmachineCore

private struct Row: Equatable, Identifiable {
    let id: String
    var port: Int
}

final class StableListTests: XCTestCase {
    func testAnEqualListIsUnchanged() {
        let rows = [Row(id: "a", port: 1), Row(id: "b", port: 2)]
        let merge = StableList.merge(old: rows, new: rows)
        XCTAssertFalse(merge.changed)
        XCTAssertEqual(merge.list, rows)
    }

    func testOnlyWhatChangedIsReported() {
        let old = [Row(id: "a", port: 1), Row(id: "b", port: 2), Row(id: "c", port: 3)]
        let new = [Row(id: "a", port: 1), Row(id: "b", port: 20), Row(id: "d", port: 4)]

        let merge = StableList.merge(old: old, new: new)

        XCTAssertTrue(merge.changed)
        XCTAssertEqual(merge.inserted, ["d"])
        XCTAssertEqual(merge.removed, ["c"])
        XCTAssertEqual(merge.updated, ["b"])
    }

    func testAReorderAloneKeepsTheOrderOnScreen() {
        let old = [Row(id: "b", port: 2), Row(id: "a", port: 1)]
        let new = [Row(id: "a", port: 1), Row(id: "b", port: 2)]

        let merge = StableList.merge(old: old, new: new)

        XCTAssertFalse(merge.changed)
        XCTAssertEqual(merge.list.map(\.id), ["b", "a"])
    }

    func testAnInsertTakesTheAnswersOrder() {
        let old = [Row(id: "b", port: 2), Row(id: "a", port: 1)]
        let new = [Row(id: "a", port: 1), Row(id: "c", port: 3), Row(id: "b", port: 2)]

        let merge = StableList.merge(old: old, new: new)

        XCTAssertEqual(merge.list.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(merge.inserted, ["c"])
        XCTAssertTrue(merge.updated.isEmpty)
    }

    func testIdentitiesOfKeptRowsAreTheSame() {
        let old = [Row(id: "a", port: 1), Row(id: "b", port: 2)]
        let new = [Row(id: "a", port: 1), Row(id: "b", port: 5)]
        let merge = StableList.merge(old: old, new: new)
        XCTAssertEqual(merge.list.map(\.id), old.map(\.id))
        XCTAssertEqual(merge.list[1].port, 5)
    }

    func testAFirstAnswerIsAllInserted() {
        let merge = StableList.merge(old: [Row](), new: [Row(id: "a", port: 1)])
        XCTAssertTrue(merge.changed)
        XCTAssertEqual(merge.inserted, ["a"])
    }
}
