import XCTest
@testable import DevmachineApp

final class BGTaskBytesTests: XCTestCase {
    private func card() -> BGTask {
        BGTask(id: UUID(), label: "Downloading a.zip", completed: 0, total: 0, showsCount: false)
    }

    func testABytesCardWithNoSizeYetIsStillRunning() {
        XCTAssertFalse(card().isDone)
        XCTAssertNil(card().detail)
    }

    func testAnEmptyCountedJobIsDone() {
        XCTAssertTrue(BGTask(id: UUID(), label: "Connecting workspaces…", completed: 0, total: 0).isDone)
    }

    func testAKnownTotalFillsTheBarWithNoText() {
        var task = card()
        task.showBytes(done: 300, total: 1200)
        XCTAssertEqual(task.completed, 300)
        XCTAssertEqual(task.total, 1200)
        XCTAssertNil(task.detail)
        XCTAssertFalse(task.isDone)

        task.showBytes(done: 1200, total: 1200)
        XCTAssertTrue(task.isDone)
    }

    func testNoTotalSaysHowMuchHasArrived() {
        var task = card()
        task.showBytes(done: 0, total: nil)
        XCTAssertNil(task.detail)

        task.showBytes(done: 5_000_000, total: nil)
        XCTAssertEqual(task.total, 0)
        XCTAssertEqual(task.detail, ByteCountFormatter.string(fromByteCount: 5_000_000, countStyle: .file))
        XCTAssertFalse(task.isDone)
    }

    func testMoreBytesThanTheTotalNeverOverfillsTheBar() {
        var task = card()
        task.showBytes(done: 1300, total: 1200)
        XCTAssertEqual(task.completed, 1200)
    }
}
