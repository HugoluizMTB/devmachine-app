import XCTest
@testable import DevmachineCore

final class FailureCauseTests: XCTestCase {
    func testCommonFailuresAreRecognised() {
        XCTAssertEqual(FailureCause(message: "alice@203.0.113.10: Permission denied (publickey)."), .permissionDenied)
        XCTAssertEqual(FailureCause(message: "ssh: connect to host 203.0.113.10 port 22: Operation timed out"), .timedOut)
        XCTAssertEqual(FailureCause(message: "ssh: Could not resolve hostname acme-devmachine"), .unreachable)
        XCTAssertEqual(FailureCause(message: "connect to host: Connection refused"), .unreachable)
        XCTAssertEqual(FailureCause(message: "zsh: command not found: devmachine"), .missingCommand)
        XCTAssertEqual(FailureCause(message: "gh: To get started with GitHub CLI, please run: gh auth login"), .signInNeeded)
        XCTAssertNil(FailureCause(message: "exit status 3"))
    }

    func testEveryCauseReadsAsOnePlainSentence() {
        for cause in FailureCause.allCases {
            XCTAssertTrue(cause.summary.hasSuffix("."), "\(cause)")
            XCTAssertFalse(cause.summary.contains("\n"), "\(cause)")
        }
        XCTAssertEqual(FailureCause.unreachable.summary, "The machine can't be reached right now.")
    }
}
