import XCTest
@testable import DevmachineCore

final class JobFailureTests: XCTestCase {
    func testLastErrorLine() {
        XCTAssertEqual(JobFailure.cause(["error: first", "noise", "Error: ssh: connect refused"]),
                       "ssh: connect refused")
    }

    func testNilWithoutErrorLine() {
        XCTAssertNil(JobFailure.cause(["ok"]))
    }
}
