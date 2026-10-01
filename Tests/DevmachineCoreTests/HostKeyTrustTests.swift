import XCTest
@testable import DevmachineCore

final class HostKeyTrustTests: XCTestCase {
    private let changedJSON = """
    {
      "machine": "box",
      "address": "100.64.0.7",
      "status": "changed",
      "key_type": "ecdsa-sha2-nistp256",
      "current_fingerprint": "SHA256:oldOLDold0000000000000000000000000000000000",
      "presented_fingerprint": "SHA256:newNEWnew1111111111111111111111111111111111",
      "check": true,
      "changed": false,
      "fix": "devmachine machines trust box --replace",
      "verify": "ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub"
    }
    """

    private func report(_ json: String) throws -> HostKeyReport {
        try HostKeyReport.parse(json)
    }

    func testAChangedKeyReportCarriesBothFingerprintsAndTheVerifyCommand() throws {
        let r = try report(changedJSON)
        XCTAssertEqual(r.machine, "box")
        XCTAssertEqual(r.address, "100.64.0.7")
        XCTAssertEqual(r.status, .changed)
        XCTAssertEqual(r.keyType, "ecdsa-sha2-nistp256")
        XCTAssertEqual(r.currentFingerprint, "SHA256:oldOLDold0000000000000000000000000000000000")
        XCTAssertNil(r.currentKeyType)
        XCTAssertEqual(r.presentedFingerprint, "SHA256:newNEWnew1111111111111111111111111111111111")
        XCTAssertEqual(r.verify, "ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub")
    }

    func testAMissingKeyHasNoCurrentFingerprint() throws {
        let r = try report("""
        {"machine":"box","address":"203.0.113.10","status":"missing","key_type":"ssh-ed25519",
         "presented_fingerprint":"SHA256:abc","check":true,"changed":false,
         "fix":"devmachine machines trust box"}
        """)
        XCTAssertEqual(r.status, .missing)
        XCTAssertNil(r.currentFingerprint)
        XCTAssertNil(r.verify)
    }

    func testAnUnknownStatusIsNotReadAsSafe() throws {
        XCTAssertThrowsError(try report("""
        {"machine":"box","address":"a","status":"weird","key_type":"t","presented_fingerprint":"f",
         "check":true,"changed":false}
        """))
    }

    func testCheckNeverWrites() {
        XCTAssertEqual(
            HostKeyTrust.checkArguments(machine: "box"),
            ["--format", "json", "machines", "trust", "box", "--check"])
    }

    func testTrustReplacesOnlyAChangedKey() throws {
        XCTAssertEqual(
            HostKeyTrust.trustArguments(for: try report(changedJSON)),
            ["--format", "json", "machines", "trust", "box", "--replace", "--yes",
             "--expect", "SHA256:newNEWnew1111111111111111111111111111111111"])
        let missing = try report("""
        {"machine":"box","address":"a","status":"missing","key_type":"t","presented_fingerprint":"f",
         "check":true,"changed":false}
        """)
        XCTAssertEqual(
            HostKeyTrust.trustArguments(for: missing),
            ["--format", "json", "machines", "trust", "box", "--yes", "--expect", "f"])
    }

    func testAMatchingKeyHasNothingToTrust() throws {
        let matching = try report("""
        {"machine":"box","address":"a","status":"matching","key_type":"t","presented_fingerprint":"f",
         "current_fingerprint":"f","check":true,"changed":false}
        """)
        XCTAssertNil(HostKeyTrust.trustArguments(for: matching))
    }

    func testPastedConsoleOutputConfirmsOnlyTheExactPresentedFingerprint() throws {
        let r = try report(changedJSON)
        let console = "256 SHA256:newNEWnew1111111111111111111111111111111111 root@box (ECDSA)\n"
        XCTAssertTrue(HostKeyTrust.confirms(console, report: r))
        XCTAssertTrue(HostKeyTrust.confirms("  SHA256:newNEWnew1111111111111111111111111111111111  ", report: r))
        // The old key, a prefix, a longer key or a different case never confirm.
        XCTAssertFalse(HostKeyTrust.confirms("256 SHA256:oldOLDold0000000000000000000000000000000000 root@box", report: r))
        XCTAssertFalse(HostKeyTrust.confirms("SHA256:newNEWnew11111111", report: r))
        XCTAssertFalse(HostKeyTrust.confirms("SHA256:newNEWnew1111111111111111111111111111111111X", report: r))
        XCTAssertFalse(HostKeyTrust.confirms("sha256:newnewnew1111111111111111111111111111111111", report: r))
        XCTAssertFalse(HostKeyTrust.confirms("", report: r))
    }

    func testOnlySSHsOwnHostKeyWordsReadAsAHostKeyRejection() {
        for message in [
            "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @",
            "Host key verification failed.",
            "No ED25519 host key is known for acme-devmachine and you have requested strict checking.\nHost key verification failed.",
        ] {
            XCTAssertTrue(HostKeyTrust.isHostKeyRejection(message), message)
            XCTAssertEqual(SSHFailure.classify(exitCode: 255, stderr: message), .hostKeyRejected, message)
        }
        XCTAssertFalse(HostKeyTrust.isHostKeyRejection("ssh: connect to host 203.0.113.10 port 22: Operation timed out"))
        XCTAssertEqual(
            SSHFailure.classify(exitCode: 255, stderr: "ssh: connect to host 203.0.113.10 port 22: Connection refused"),
            .unreachable)
        XCTAssertNil(SSHFailure.classify(exitCode: 1, stderr: "Host key verification failed."))
    }

    func testAnOlderCLIRefusesTheChangedKeyWithoutJSON() {
        let stderr = "error: host key changed for machine \"box\" at 100.64.0.7: trusted SHA256:a, presented SHA256:b; "
            + "this can mean an attack, a wrong address, or a deliberate rebuild; verify it before using --replace"
        XCTAssertTrue(HostKeyTrust.isOlderCLIRefusal(stderr))
        XCTAssertFalse(HostKeyTrust.isOlderCLIRefusal("error: no address answered while scanning"))
    }

    func testHostKeyCauseIsSaidPlainly() {
        XCTAssertEqual(FailureCause(message: "Host key verification failed."), .hostKeyRejected)
        XCTAssertEqual(
            FailureCause.hostKeyRejected.summary,
            "The machine answered with an SSH identity this Mac doesn't trust.")
    }
}
