import XCTest
@testable import DevmachineCore

final class SyncSummaryTests: XCTestCase {
    func testReadsTheLastSummaryLine() {
        let lines = [
            "PLAY RECAP *********",
            "main : ok=40 changed=2 unreachable=0 failed=0 skipped=3",
            "main: ok=41 changed=3 failed=0",
        ]
        XCTAssertEqual(SyncSummary.parse(lines), SyncSummary(ok: 41, changed: 3, failed: 0))
    }

    func testIgnoresColourCodes() {
        XCTAssertEqual(SyncSummary.parse(["\u{1B}[32mmain: ok=1 changed=0 failed=0\u{1B}[0m"]),
                       SyncSummary(ok: 1, changed: 0, failed: 0))
    }

    func testNilWithoutSummary() {
        XCTAssertNil(SyncSummary.parse(["TASK [docker : install]", "ok: [main]"]))
    }
}
