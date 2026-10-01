import XCTest
@testable import DevmachineCore

final class CLISelfUpdateTests: XCTestCase {
    func testItRunsOnlyTheCLIStep() {
        XCTAssertEqual(CLISelfUpdate.arguments, ["update", "--cli-only"])
    }

    func testOnlyACLIThatKnowsTheFlagIsUpdatedFromTheApp() {
        XCTAssertFalse(CLISelfUpdate.supportsCLIOnly(SemanticVersion("0.7.22")!))
        XCTAssertTrue(CLISelfUpdate.supportsCLIOnly(SemanticVersion("0.7.23")!))
        XCTAssertTrue(CLISelfUpdate.supportsCLIOnly(SemanticVersion("0.8.0")!))
    }

    func testAnUnknownFlagIsSeenInTheOutput() {
        XCTAssertTrue(CLISelfUpdate.isUnknownFlag(["error: unknown flag: --cli-only"]))
        XCTAssertFalse(CLISelfUpdate.isUnknownFlag(["error: updating the CLI: no route to host"]))
    }

    func testTheCauseIsTheLastErrorLine() {
        let lines = ["==> CLI", "  downloading v0.8.0", "error: updating the CLI: checksum mismatch"]
        XCTAssertEqual(CLISelfUpdate.failureCause(lines), "updating the CLI: checksum mismatch")
        XCTAssertNil(CLISelfUpdate.failureCause(["==> CLI"]))
    }

    func testTheEnvironmentFindsHomebrew() {
        let environment = CLISelfUpdate.environment(base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/alice"])
        XCTAssertEqual(environment["PATH"], "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        XCTAssertEqual(environment["HOME"], "/Users/alice")
        XCTAssertEqual(CLISelfUpdate.environment(base: [:])["PATH"],
                       "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    func testTheNewVersionMustReachTheRelease() {
        let expected = SemanticVersion("0.8.0")!
        XCTAssertEqual(CLISelfUpdate.confirmedVersion(versionOutput: "0.8.0\n", expected: expected), expected)
        XCTAssertNil(CLISelfUpdate.confirmedVersion(versionOutput: "0.7.23\n", expected: expected))
        XCTAssertNil(CLISelfUpdate.confirmedVersion(versionOutput: "dev\n", expected: expected))
    }
}
