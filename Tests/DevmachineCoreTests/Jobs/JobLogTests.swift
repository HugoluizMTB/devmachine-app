import XCTest
@testable import DevmachineCore

final class JobLogTests: XCTestCase {
    func testKeepsTheNewestLinesUnderTheCap() {
        var log = JobLog(cap: 3)
        log.append(contentsOf: ["1", "2", "3", "4", "5"])
        XCTAssertEqual(log.lines, ["3", "4", "5"])
        XCTAssertEqual(log.dropped, 2)
        XCTAssertEqual(log.shown.first, "… 2 earlier lines not kept")
    }

    func testShownIsLinesWhenNothingDropped() {
        var log = JobLog(cap: 3)
        log.append(contentsOf: ["a"])
        XCTAssertEqual(log.shown, ["a"])
    }

    func testTenThousandLinesStayCapped() {
        var log = JobLog()
        for chunk in stride(from: 0, to: 10_000, by: 100) {
            log.append(contentsOf: (chunk..<chunk + 100).map(String.init))
        }
        XCTAssertEqual(log.lines.count, 5000)
        XCTAssertEqual(log.lines.last, "9999")
    }
}
