import XCTest
import DevmachineCore
@testable import DevmachineApp

final class HostKeyStoreTests: XCTestCase {
    private static let changed = """
    {"machine":"box","address":"100.64.0.7","status":"changed","key_type":"ecdsa-sha2-nistp256",
     "current_key_type":"ecdsa-sha2-nistp256","current_fingerprint":"SHA256:old",
     "presented_fingerprint":"SHA256:new","check":true,"changed":false,
     "fix":"devmachine machines trust box --replace --expect SHA256:new",
     "verify":"ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub"}
    """

    @MainActor
    func testACheckThatFindsAChangedKeyAsksForAReview() async throws {
        let runner = FakeHostKeyRunner([CLIOutput(stdout: Self.changed, stderr: "", exitCode: 0)])
        let store = HostKeyStore(runner: runner)
        await store.check("box")

        guard case let .review(report) = store.phase(for: "box") else {
            return XCTFail("phase = \(String(describing: store.phase(for: "box")))")
        }
        XCTAssertEqual(report.presentedFingerprint, "SHA256:new")
        XCTAssertEqual(runner.calls, [["--format", "json", "machines", "trust", "box", "--check"]])
    }

    @MainActor
    func testAKeyThatMatchesNeedsNoReview() async {
        let matching = """
        {"machine":"box","address":"a","status":"matching","key_type":"t","current_fingerprint":"f",
         "presented_fingerprint":"f","check":true,"changed":false}
        """
        let store = HostKeyStore(runner: FakeHostKeyRunner([CLIOutput(stdout: matching, stderr: "", exitCode: 0)]))
        await store.check("box")
        XCTAssertEqual(store.phase(for: "box"), .matching)
    }

    @MainActor
    func testAnOlderCLIThatRefusesTheChangedKeyAsksForAnUpdate() async {
        let refusal = "error: host key changed for machine \"box\" at 100.64.0.7: trusted SHA256:old, presented SHA256:new; "
            + "this can mean an attack, a wrong address, or a deliberate rebuild; verify it before using --replace"
        let store = HostKeyStore(runner: FakeHostKeyRunner([CLIOutput(stdout: "", stderr: refusal, exitCode: 1)]))
        await store.check("box")
        XCTAssertEqual(store.phase(for: "box"), .needsNewerCLI)
    }

    @MainActor
    func testAMachineThatDoesNotAnswerSaysSoWithTheExactError() async {
        let error = "error: no address answered while scanning box: dial tcp 100.64.0.7:22: i/o timeout"
        let store = HostKeyStore(runner: FakeHostKeyRunner([CLIOutput(stdout: "", stderr: error, exitCode: 1)]))
        await store.check("box")
        guard case let .failed(state) = store.phase(for: "box") else { return XCTFail("not failed") }
        XCTAssertEqual(state.details, error)
        XCTAssertEqual(state.cause, FailureCause.timedOut.summary)
    }

    @MainActor
    func testNothingIsTrustedUntilThePastedOutputHoldsThePresentedFingerprint() async throws {
        let runner = FakeHostKeyRunner([CLIOutput(stdout: "{}", stderr: "", exitCode: 0)])
        let store = HostKeyStore(runner: runner)
        var trusted: [String] = []
        store.onTrusted = { trusted.append($0) }
        let report = try HostKeyReport.parse(Self.changed)

        await store.trust("box", report: report, pasted: "256 SHA256:old root@box (ECDSA)")
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(trusted.isEmpty)

        await store.trust("box", report: report, pasted: "256 SHA256:new root@box (ECDSA)")
        XCTAssertEqual(runner.calls, [[
            "--format", "json", "machines", "trust", "box", "--replace", "--yes", "--expect", "SHA256:new",
        ]])
        XCTAssertEqual(store.phase(for: "box"), .trusted)
        XCTAssertEqual(trusted, ["box"])
    }

    @MainActor
    func testADifferentKeyAtReplaceTimeIsRefusedAndSaidPlainly() async throws {
        let stderr = "error: machine \"box\" at 100.64.0.7 presented SHA256:other, not the expected SHA256:new; nothing was written"
        let store = HostKeyStore(runner: FakeHostKeyRunner([CLIOutput(stdout: "", stderr: stderr, exitCode: 1)]))
        var trusted: [String] = []
        store.onTrusted = { trusted.append($0) }

        await store.trust("box", report: try HostKeyReport.parse(Self.changed), pasted: "SHA256:new")
        guard case let .failed(state) = store.phase(for: "box") else { return XCTFail("not failed") }
        XCTAssertEqual(
            state.cause,
            "The machine presented a different key than the one you checked. Nothing was written.")
        XCTAssertEqual(state.details, stderr)
        XCTAssertTrue(trusted.isEmpty)
    }

    func testAHostKeyRefusalReadsAsItsOwnProblem() {
        let stderr = "Host key verification failed."
        let problem = SessionProblem(SessionStoreError(failure: .hostKeyRejected, stderr: stderr))
        XCTAssertTrue(problem.isHostKeyRejected)
        let presentation = problem.presentation(workspace: "acme")
        XCTAssertEqual(presentation.title, "Couldn't connect to acme")
        XCTAssertEqual(presentation.details, stderr)
        XCTAssertEqual(
            presentation.cause,
            FailureCause.hostKeyRejected.summary + " Review the new key before connecting again.")
    }
}

private final class FakeHostKeyRunner: HostKeyRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [CLIOutput]
    private var recorded: [[String]] = []

    init(_ outputs: [CLIOutput]) { self.outputs = outputs }

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ arguments: [String]) async throws -> CLIOutput {
        lock.withLock {
            recorded.append(arguments)
            return outputs.isEmpty ? CLIOutput(stdout: "", stderr: "unexpected call", exitCode: 1) : outputs.removeFirst()
        }
    }
}
