import XCTest
@testable import DevmachineCore

final class CommandMRUTests: XCTestCase {
    func testRecordingPutsTheIDFirst() {
        let mru = CommandMRU(ids: ["a", "b"]).recording("c")
        XCTAssertEqual(mru.ids, ["c", "a", "b"])
    }

    func testRecordingAnIDAgainMovesItToTheFrontWithoutADuplicate() {
        let mru = CommandMRU(ids: ["a", "b", "c"]).recording("c")
        XCTAssertEqual(mru.ids, ["c", "a", "b"])
    }

    func testTheListKeepsOnlyTheCapacity() {
        var mru = CommandMRU(ids: [], capacity: 3)
        for id in ["a", "b", "c", "d"] { mru = mru.recording(id) }
        XCTAssertEqual(mru.ids, ["d", "c", "b"])
    }

    func testTheMostRecentGetsTheBiggestBoost() {
        let mru = CommandMRU(ids: ["a", "b"])
        XCTAssertGreaterThan(mru.boost(for: "a"), mru.boost(for: "b"))
        XCTAssertGreaterThan(mru.boost(for: "b"), 0)
        XCTAssertEqual(mru.boost(for: "z"), 0)
    }

    func testAnInitialListLongerThanTheCapacityIsCut() {
        XCTAssertEqual(CommandMRU(ids: ["a", "b", "c"], capacity: 2).ids, ["a", "b"])
    }
}
