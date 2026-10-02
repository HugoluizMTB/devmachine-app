import XCTest
@testable import DevmachineCore

final class LogTextTests: XCTestCase {
    func testColourCodesAreTakenOut() {
        XCTAssertEqual(LogText.plain("\u{1B}[2m$ devmachine sync\u{1B}[0m"), "$ devmachine sync")
        XCTAssertEqual(LogText.plain("\u{1B}]0;title\u{07}ok"), "ok")
    }

    func testAProgressBarRedrawnInPlaceShowsItsLastState() {
        XCTAssertEqual(LogText.plain("10%\r50%\r100%"), "100%")
        XCTAssertEqual(LogText.plain("done\r"), "done")
    }

    func testTabsBecomeSpaces() {
        XCTAssertEqual(LogText.plain("a\tb"), "a    b")
    }
}
