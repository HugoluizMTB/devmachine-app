import XCTest
@testable import DevmachineCore

final class LoginFailureTests: XCTestCase {
    func testTheWaysSSHAndTheCLISayTheLoginWasRefused() {
        for message in [
            "alice@203.0.113.7: Permission denied (publickey).",
            "alice@203.0.113.7: Permission denied (publickey,password,keyboard-interactive).",
            "Permission denied, please try again.",
            "Received disconnect from 203.0.113.7 port 22:2: Too many authentication failures",
            "error: the key does not log in yet and no password was given",
            "error: running stats on acme: exit status 255\nalice@203.0.113.7: Permission denied (publickey).",
            "Disconnected from 203.0.113.7 port 22: No more authentication methods available",
            "login-refused",
        ] {
            XCTAssertEqual(LoginFailure(message: message), .refused, message)
        }
    }

    func testTheSessionsStatusOfARefusedLogin() {
        XCTAssertEqual(LoginFailure(sessionsStatus: "login-refused"), .refused)
        XCTAssertNil(LoginFailure(sessionsStatus: "unreachable"))
        XCTAssertNil(LoginFailure(sessionsStatus: "login-waiting"))
        XCTAssertNil(LoginFailure(sessionsStatus: "host-key-rejected"))
    }

    func testAConnectionRefusedIsToldApart() {
        XCTAssertEqual(
            LoginFailure(message: "ssh: connect to host 203.0.113.7 port 22: Connection refused"), .connectionRefused)
    }

    func testOtherFailuresAreNeither() {
        for message in [
            "ssh: connect to host 203.0.113.7 port 22: Operation timed out",
            "Host key verification failed.",
            "rm: cannot remove '/home/alice/dev/dash/build': Permission denied",
            "the package devmachine-app is not installed on acme",
            "",
        ] {
            XCTAssertNil(LoginFailure(message: message), message)
        }
    }
}

final class LoginHoldsTests: XCTestCase {
    private let refusal = "alice@203.0.113.7: Permission denied (publickey)."
    private let connectionRefused = "ssh: connect to host 203.0.113.7 port 22: Connection refused"

    func testARefusedLoginHoldsItsMachineOnly() {
        var holds = LoginHolds()
        XCTAssertTrue(holds.record(message: refusal, machine: "acme"))
        XCTAssertTrue(holds.isHeld("acme"))
        XCTAssertFalse(holds.isHeld("beta"))
        XCTAssertEqual(holds.hold(for: "acme")?.reason, .loginRefused)
        XCTAssertEqual(holds.hold(for: "acme")?.detail, refusal)
    }

    func testTheHoldNeverEndsOnItsOwn() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        XCTAssertFalse(holds.record(message: refusal, machine: "acme"), "a hold already on is not news")
        holds.record(message: "ssh: connect to host 203.0.113.7 port 22: Operation timed out", machine: "acme")
        XCTAssertTrue(holds.isHeld("acme"))
    }

    func testOtherFailuresHoldNothing() {
        var holds = LoginHolds()
        XCTAssertFalse(holds.record(message: "ssh: connect to host 203.0.113.7 port 22: Operation timed out", machine: "acme"))
        XCTAssertFalse(holds.record(message: connectionRefused, machine: "acme"))
        XCTAssertFalse(holds.isHeld("acme"))
    }

    func testAConnectionRefusedAfterARefusedLoginIsAProbableBlock() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        XCTAssertTrue(holds.beginRetry("acme"))
        holds.record(message: connectionRefused, machine: "acme")
        XCTAssertTrue(holds.isHeld("acme"))
        XCTAssertEqual(holds.hold(for: "acme")?.reason, .probablyBlocked)
        XCTAssertTrue(holds.hold(for: "acme")?.message.contains("Wait about 10 minutes, then Retry.") == true)
    }

    func testRetryKeepsAutomaticCallsHeldUntilItsOneAttemptAnswers() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        XCTAssertTrue(holds.beginRetry("acme"))
        XCTAssertTrue(holds.isHeld("acme"))
        XCTAssertTrue(holds.isRetrying("acme"))
        XCTAssertFalse(holds.beginRetry("acme"), "a second Retry while the first runs adds no attempt")
        holds.record(message: refusal, machine: "acme")
        XCTAssertTrue(holds.isHeld("acme"))
        XCTAssertFalse(holds.isRetrying("acme"))
    }

    func testASuccessEndsTheHoldAndForgetsTheRefusals() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        holds.beginRetry("acme")
        holds.recordSuccess(machine: "acme")
        XCTAssertFalse(holds.isHeld("acme"))
        XCTAssertFalse(holds.record(message: connectionRefused, machine: "acme"))
    }

    func testASuccessOutsideRetryLeavesTheHold() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        holds.recordSuccess(machine: "acme")
        XCTAssertTrue(holds.isHeld("acme"))
    }

    func testRetryOnAMachineNotHeldDoesNothing() {
        var holds = LoginHolds()
        XCTAssertFalse(holds.beginRetry("acme"))
    }

    func testAnotherFailureOnTheRetryEndsTheHold() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        holds.beginRetry("acme")
        holds.record(message: "ssh: connect to host 203.0.113.7 port 22: Operation timed out", machine: "acme")
        XCTAssertFalse(holds.isHeld("acme"))
    }

    func testAChangedMachineEntryEndsItsHold() {
        var holds = LoginHolds()
        holds.configurationRead(["acme": "203.0.113.7|alice|22|", "beta": "203.0.113.8|bob|22|"])
        holds.record(message: refusal, machine: "acme")
        holds.record(message: refusal, machine: "beta")
        XCTAssertEqual(holds.configurationRead(["acme": "203.0.113.7|alice|22|", "beta": "203.0.113.8|bob|22|"]), [])
        XCTAssertTrue(holds.isHeld("acme"))
        let released = holds.configurationRead(["acme": "203.0.113.7|alice|22|~/.ssh/acme", "beta": "203.0.113.8|bob|22|"])
        XCTAssertEqual(released, ["acme"])
        XCTAssertFalse(holds.isHeld("acme"))
        XCTAssertTrue(holds.isHeld("beta"))
        XCTAssertFalse(holds.record(message: connectionRefused, machine: "acme"), "the change forgets old refusals")
    }

    func testAHoldMadeBeforeTheFirstConfigurationReadIsKept() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        XCTAssertEqual(holds.configurationRead(["acme": "203.0.113.7|alice|22|"]), [])
        XCTAssertTrue(holds.isHeld("acme"))
    }

    func testARemovedMachineLosesItsHold() {
        var holds = LoginHolds()
        holds.configurationRead(["acme": "203.0.113.7|alice|22|"])
        holds.record(message: refusal, machine: "acme")
        XCTAssertEqual(holds.configurationRead([:]), ["acme"])
        XCTAssertFalse(holds.isHeld("acme"))
    }

    func testTheRefusedLoginSaysWhatHappenedAndWhy() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        let hold = holds.hold(for: "acme")
        XCTAssertEqual(hold?.title, "The server refused the login")
        XCTAssertTrue(hold?.message.contains("stopped trying so the server does not block this Mac") == true)
    }

    func testRetryWithNothingToTryKeepsTheHold() {
        var holds = LoginHolds()
        holds.record(message: refusal, machine: "acme")
        holds.beginRetry("acme")
        holds.endRetry("acme")
        XCTAssertTrue(holds.isHeld("acme"))
        XCTAssertTrue(holds.beginRetry("acme"))
    }

    func testTheEntryChangesWithAnyPartOfTheLogin() {
        let base = LoginHolds.entry(hosts: ["203.0.113.7"], user: "alice", port: 22, key: nil, agentKey: nil)
        XCTAssertEqual(base, LoginHolds.entry(hosts: ["203.0.113.7"], user: "alice", port: 22, key: "", agentKey: nil))
        for other in [
            LoginHolds.entry(hosts: ["203.0.113.8"], user: "alice", port: 22, key: nil, agentKey: nil),
            LoginHolds.entry(hosts: ["203.0.113.7"], user: "bob", port: 22, key: nil, agentKey: nil),
            LoginHolds.entry(hosts: ["203.0.113.7"], user: "alice", port: 2222, key: nil, agentKey: nil),
            LoginHolds.entry(hosts: ["203.0.113.7"], user: "alice", port: 22, key: "/Users/alice/.ssh/acme", agentKey: nil),
            LoginHolds.entry(hosts: ["203.0.113.7"], user: "alice", port: 22, key: nil, agentKey: "SHA256:abc"),
        ] {
            XCTAssertNotEqual(base, other)
        }
    }
}
