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

    func testOnlyAnSSHLoginRefusalReadsAsARefusedLogin() {
        for message in [
            "alice@203.0.113.10: Permission denied (publickey).",
            "alice@203.0.113.10: Permission denied (publickey,password,keyboard-interactive).",
            "Permission denied, please try again.",
            "Received disconnect from 203.0.113.10 port 22:2: Too many authentication failures",
        ] {
            XCTAssertEqual(FailureCause(message: message), .permissionDenied, message)
            XCTAssertTrue(FailureCause.isSSHLoginRefused(message), message)
        }
    }

    func testAFileThatCannotBeChangedIsNotALoginFailure() {
        for message in [
            "error: failed to delete '/home/alice/dev/dash/.worktrees/old': Permission denied",
            "rm: cannot remove '/home/alice/dev/dash/build/cache': Permission denied",
            "sh: 1: cannot create /home/alice/out.txt: Permission denied",
        ] {
            XCTAssertEqual(FailureCause(message: message), .fileAccessDenied, message)
            XCTAssertFalse(FailureCause.isSSHLoginRefused(message), message)
        }
        XCTAssertNotEqual(FailureCause.fileAccessDenied.summary, FailureCause.permissionDenied.summary)
        XCTAssertFalse(FailureCause.fileAccessDenied.summary.contains("SSH"))
    }

    func testSSHExitingWithAFileErrorIsNotAnAuthFailure() {
        XCTAssertEqual(SSHFailure.classify(exitCode: 255, stderr: "alice@acme: Permission denied (publickey)."), .authDenied)
        XCTAssertEqual(
            SSHFailure.classify(exitCode: 255, stderr: "error: failed to delete '/home/alice/x': Permission denied"),
            .unreachable)
        XCTAssertNil(SSHFailure.classify(exitCode: 1, stderr: "Permission denied (publickey)."))
    }

    func testEveryCauseReadsAsOnePlainSentence() {
        for cause in FailureCause.allCases {
            XCTAssertTrue(cause.summary.hasSuffix("."), "\(cause)")
            XCTAssertFalse(cause.summary.contains("\n"), "\(cause)")
        }
        XCTAssertEqual(FailureCause.unreachable.summary, "The machine can't be reached right now.")
    }
}
