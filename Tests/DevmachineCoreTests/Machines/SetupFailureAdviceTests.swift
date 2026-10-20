import XCTest
@testable import DevmachineCore

final class SetupFailureAdviceTests: XCTestCase {
    func testAnOutdatedXcodeSaysToUpdateItOrSkipHomebrew() {
        let advice = SetupFailureAdvice.advice(
            for: .installCLI,
            lines: ["==> Installing devmachine", "Error: Your Xcode (14.1) is too outdated.",
                    "Please update to Xcode 16.0 (or delete it)."])
        XCTAssertEqual(advice?.cause, .outdatedXcode)
        XCTAssertTrue(advice?.whatToDo.contains("Software Update") == true)
    }

    func testOutdatedCommandLineToolsAreTheSameCause() {
        let advice = SetupFailureAdvice.advice(
            for: .addPackage("docker"), lines: ["Error: Your Command Line Tools (CLT) are too outdated."])
        XCTAssertEqual(advice?.cause, .outdatedXcode)
    }

    func testACLIDownloadThatFailedSaysToCheckTheConnection() {
        let advice = SetupFailureAdvice.advice(
            for: .installCLI, lines: ["curl: (6) Could not resolve host: mydevmachine.sh"])
        XCTAssertEqual(advice?.cause, .cliDownload)
    }

    func testALimaDownloadThatFailedSaysToCheckTheConnection() {
        let advice = SetupFailureAdvice.advice(
            for: .installLima, lines: ["Asking GitHub for Lima's latest release…", "The Internet connection appears to be offline."])
        XCTAssertEqual(advice?.cause, .limaDownload)
    }

    func testALimaChecksumMismatchIsNotADownloadProblem() {
        let advice = SetupFailureAdvice.advice(
            for: .installLima,
            lines: ["The download does not match Lima's published checksum (expected a, got b). Nothing was installed."])
        XCTAssertEqual(advice?.cause, .limaChecksum)
    }

    func testAKeyThatChangedSaysTheServerIsNotTheOneConfirmed() {
        let advice = SetupFailureAdvice.advice(
            for: .addMachine,
            lines: ["error: the server presented SHA256:abc, which does not match the fingerprint you gave (SHA256:def)"])
        XCTAssertEqual(advice?.cause, .hostKeyMismatch)

        let ssh = SetupFailureAdvice.advice(
            for: .addMachine, lines: ["@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@"])
        XCTAssertEqual(ssh?.cause, .hostKeyMismatch)
    }

    func testARefusedLoginSaysTheKeyOrPasswordIsWrong() {
        let advice = SetupFailureAdvice.advice(
            for: .addMachine, lines: ["root@203.0.113.10: Permission denied (publickey,password)."])
        XCTAssertEqual(advice?.cause, .loginRefused)
    }

    func testAServerThatCannotBeReachedSaysSo() {
        let advice = SetupFailureAdvice.advice(
            for: .addMachine, lines: ["ssh: connect to host 203.0.113.10 port 22: Connection refused"])
        XCTAssertEqual(advice?.cause, .unreachable)
    }

    func testAMissingLimaWhenCreatingTheMachineSaysToInstallIt() {
        let advice = SetupFailureAdvice.advice(
            for: .createLocal, lines: ["error: limactl was not found: install Lima first (brew install lima)"])
        XCTAssertEqual(advice?.cause, .limaMissing)
    }

    func testTheLatestCauseWinsAndUnknownLinesGiveNoAdvice() {
        XCTAssertNil(SetupFailureAdvice.advice(for: .sync, lines: ["TASK [base : apt] failed for no reason"]))
        let advice = SetupFailureAdvice.advice(
            for: .sync, lines: ["Connection refused", "retrying", "Permission denied (publickey)."])
        XCTAssertEqual(advice?.cause, .loginRefused)
    }

    func testEveryCauseHasATitleAndWhatToDo() {
        for cause in SetupFailureAdvice.Cause.allCases {
            let advice = SetupFailureAdvice(cause: cause)
            XCTAssertFalse(advice.title.isEmpty, "\(cause)")
            XCTAssertFalse(advice.whatToDo.isEmpty, "\(cause)")
        }
    }
}

final class SetupFailureHelpTests: XCTestCase {
    private let sync = MachinePlanStep(
        kind: .sync, title: "Install everything on main", arguments: ["sync", "--machine", "main", "--yes"],
        asksInTerminal: false)

    func testAnUnknownCauseStillSaysWhatRanAndWhatToDo() {
        let help = SetupFailureHelp.help(for: sync, lines: ["TASK [base] failed"])
        XCTAssertNil(help.cause)
        XCTAssertTrue(help.title.contains("Install everything on main"))
        XCTAssertEqual(help.whatToDo, "Retry runs it again; the log shows why it stopped.")
        XCTAssertEqual(help.actions, [.retry, .editAnswers("Change answers")])
    }

    func testTheDetailsKeepTheExactCommandAndTheLastLines() {
        XCTAssertEqual(
            SetupFailureHelp.details(for: sync, lines: ["TASK [base] failed"], problem: nil),
            "$ devmachine sync --machine main --yes\nTASK [base] failed")
        XCTAssertEqual(
            SetupFailureHelp.details(
                for: sync, lines: ["$ devmachine sync --machine main --yes", "TASK [base] failed"], problem: nil),
            "$ devmachine sync --machine main --yes\nTASK [base] failed")
        XCTAssertEqual(
            SetupFailureHelp.details(for: sync, lines: [], problem: "Stopped."),
            "$ devmachine sync --machine main --yes\nStopped.")
    }

    func testAnOutdatedXcodeOffersSoftwareUpdateAndTheDownloads() {
        let help = SetupFailureHelp.help(for: sync, lines: ["Error: Your Xcode (14.1) is too outdated."])
        XCTAssertEqual(help.cause, .outdatedXcode)
        XCTAssertEqual(help.actions, [
            .open("Open Software Update", SetupFailureHelp.softwareUpdate),
            .open("Xcode downloads", SetupFailureHelp.xcodeDownloads), .retry,
        ])
    }

    func testAChangedKeySendsThePersonBackToReadItAgainWithNoRetry() {
        let help = SetupFailureHelp.help(for: sync, lines: ["Host key verification failed."])
        XCTAssertEqual(help.actions, [.editAnswers("Read the key again")])
    }
}
