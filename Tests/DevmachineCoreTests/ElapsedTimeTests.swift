import XCTest
@testable import DevmachineCore

final class ElapsedTimeTests: XCTestCase {
    func testSecondsOnly() {
        XCTAssertEqual(ElapsedTime.seconds("05"), 5)
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(ElapsedTime.seconds("01:05"), 65)
    }

    func testHoursMinutesSeconds() {
        XCTAssertEqual(ElapsedTime.seconds("02:01:05"), 7265)
    }

    func testDays() {
        XCTAssertEqual(ElapsedTime.seconds("3-02:01:05"), 266_465)
    }

    func testLeadingSpacesAreIgnored() {
        XCTAssertEqual(ElapsedTime.seconds("   01:05\n"), 65)
    }

    func testGarbageIsNil() {
        XCTAssertNil(ElapsedTime.seconds("abc"))
        XCTAssertNil(ElapsedTime.seconds(""))
        XCTAssertNil(ElapsedTime.seconds("1:2:3:4"))
        XCTAssertNil(ElapsedTime.seconds("x-01:05"))
    }

    func testArgumentsListEveryPid() {
        XCTAssertEqual(ElapsedTime.psArguments([12, 34]), ["-o", "pid=,etime=", "-p", "12,34"])
    }

    func testParseMapsPidToSeconds() {
        XCTAssertEqual(
            ElapsedTime.parse("  12   01:05\n  34 3-02:01:05\n"), [12: 65, 34: 266_465])
    }

    func testParseSkipsBadLines() {
        XCTAssertEqual(ElapsedTime.parse("oops\n 7 00:09\n8 zz\n"), [7: 9])
    }
}
