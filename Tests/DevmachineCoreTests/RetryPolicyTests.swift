import XCTest
@testable import DevmachineCore

final class RetryPolicyTests: XCTestCase {
    private let offline = ["fetching https://github.com/x: dial tcp: lookup github.com: no such host"]

    func testANetworkFailureIsTriedThreeTimesWithAShortWaitBetween() {
        let policy = RetryPolicy.downloads
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.delay(afterFailedAttempts: 1, output: offline), 2)
        XCTAssertEqual(policy.delay(afterFailedAttempts: 2, output: offline), 5)
        XCTAssertNil(policy.delay(afterFailedAttempts: 3, output: offline))
    }

    func testAFailureThatIsNotTheNetworksIsNeverTriedAgain() {
        let policy = RetryPolicy.downloads
        for output in [
            ["root@203.0.113.10: Permission denied (publickey)."],
            ["error: unknown flag: --agent"],
            ["Host key verification failed."],
            ["packages-v41.tar.gz has checksum abc but the release says def"],
            ["error: no machine named acme"],
            [],
        ] {
            XCTAssertNil(policy.delay(afterFailedAttempts: 1, output: output), "\(output)")
        }
    }

    func testTheNetworkIsRecognisedFromWhatEachDownloaderPrints() {
        for line in [
            "curl: (6) Could not resolve host: mydevmachine.sh",
            "curl: (28) Operation timed out after 30001 milliseconds",
            "fetching https://github.com/x: the server answered 503",
            "read tcp 100.64.0.2:5555->203.0.113.10:443: read: connection reset by peer",
            "The Internet connection appears to be offline.",
            "ssh: connect to host 203.0.113.10 port 22: Network is unreachable",
            "net/http: TLS handshake timeout",
        ] {
            XCTAssertTrue(NetworkFailure.isTransient([line]), line)
        }
    }

    func testARefusedLoginWinsOverATimeoutInTheSameLog() {
        XCTAssertFalse(NetworkFailure.isTransient([
            "ssh: connect to host 203.0.113.10 port 22: Operation timed out",
            "alice@203.0.113.10: Permission denied (publickey,password).",
        ]))
    }

    func testOnlyStepsThatDownloadAreTriedAgain() {
        XCTAssertTrue(MachinePlanStep.installCLI.retriesOnNetworkFailure)
        XCTAssertTrue(MachinePlanStep.fetchPackages.retriesOnNetworkFailure)
        XCTAssertTrue(MachinePlanStep.checkReady("acme").retriesOnNetworkFailure)
        let sync = MachinePlanStep(kind: .sync, title: "Sync", arguments: ["sync"], asksInTerminal: false)
        let skills = MachinePlanStep(kind: .skills, title: "Skills", arguments: ["skills", "add"], asksInTerminal: false)
        XCTAssertTrue(sync.retriesOnNetworkFailure)
        XCTAssertTrue(skills.retriesOnNetworkFailure)
        let add = MachinePlanStep(kind: .addMachine, title: "Connect", arguments: ["machines", "add"], asksInTerminal: false)
        XCTAssertFalse(add.retriesOnNetworkFailure)
    }

    func testTheFinishingStepsShowTheCommandsTheyRun() {
        XCTAssertEqual(MachinePlanStep.fetchPackages.displayLine, "devmachine widgets list --format json")
        XCTAssertEqual(MachinePlanStep.checkReady("acme").displayLine, "devmachine run --machine acme -- true")
    }
}
