import XCTest
@testable import DevmachineCore

final class LRUEvictionTests: XCTestCase {
    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func testKeepsEveryKeyUnderTheCap() {
        let detached = ["a": at(1), "b": at(2)]
        XCTAssertEqual(LRUEviction.keysToEvict(detachedAt: detached, cap: 6), [])
    }

    func testKeepsEveryKeyAtTheCap() {
        let detached = ["a": at(1), "b": at(2), "c": at(3)]
        XCTAssertEqual(LRUEviction.keysToEvict(detachedAt: detached, cap: 3), [])
    }

    func testEvictsTheLongestDetachedFirst() {
        let detached = ["a": at(50), "b": at(10), "c": at(30), "d": at(20)]
        XCTAssertEqual(LRUEviction.keysToEvict(detachedAt: detached, cap: 2), ["b", "d"])
    }

    func testEvictsOnlyTheExcess() {
        let detached = ["a": at(3), "b": at(1), "c": at(2)]
        XCTAssertEqual(LRUEviction.keysToEvict(detachedAt: detached, cap: 2), ["b"])
    }

    func testCapZeroEvictsEverything() {
        let detached = ["a": at(2), "b": at(1)]
        XCTAssertEqual(LRUEviction.keysToEvict(detachedAt: detached, cap: 0), ["b", "a"])
    }

    func testNegativeCapIsTreatedAsZero() {
        let detached = ["a": at(1)]
        XCTAssertEqual(LRUEviction.keysToEvict(detachedAt: detached, cap: -3), ["a"])
    }

    func testEmptyInputEvictsNothing() {
        XCTAssertEqual(LRUEviction.keysToEvict(detachedAt: [String: Date](), cap: 6), [])
    }
}

extension LRUEvictionTests {
    func testTheCapHoldsEveryWorkspaceOfThisMachine() {
        // Ten workspaces plus a few local sessions have to fit, or moving
        // between them closes clients behind you.
        let detached = (0..<14).reduce(into: [String: Date]()) { acc, i in
            acc["ws-\(i)"] = Date(timeIntervalSince1970: Double(i))
        }
        XCTAssertTrue(LRUEviction.keysToEvict(detachedAt: detached, cap: 24).isEmpty)
    }
}
