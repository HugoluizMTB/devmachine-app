import XCTest
@testable import DevmachineCore

final class GitHeadTests: XCTestCase {
    func testBranchName() {
        XCTAssertEqual(GitHead.branch(fromAbbrevRef: "main\n"), "main")
    }

    func testDetachedHeadIsReportedAsHead() {
        XCTAssertEqual(GitHead.branch(fromAbbrevRef: "HEAD\n"), "HEAD")
    }

    func testEmptyOutputIsNil() {
        XCTAssertNil(GitHead.branch(fromAbbrevRef: ""))
        XCTAssertNil(GitHead.branch(fromAbbrevRef: "\n"))
    }

    func testArguments() {
        XCTAssertEqual(
            GitHead.abbrevRefArguments("/Users/acme/dev/acme-web"),
            ["-C", "/Users/acme/dev/acme-web", "rev-parse", "--abbrev-ref", "HEAD"])
        XCTAssertEqual(
            GitHead.shortSHAArguments("/Users/acme/dev/acme-web"),
            ["-C", "/Users/acme/dev/acme-web", "rev-parse", "--short", "HEAD"])
    }
}
