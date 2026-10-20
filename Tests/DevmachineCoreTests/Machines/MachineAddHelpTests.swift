import XCTest
@testable import DevmachineCore

final class MachineScanFailureTests: XCTestCase {
    private let refused = #"error: machine "203.0.113.20": no address answered while scanning its SSH host key: "#
        + "203.0.113.20 (dial tcp 203.0.113.20:22: connect: connection refused)"

    func testARefusedConnectionSaysNothingAnsweredOnTheSSHPort() {
        let failure = MachineScanFailure(error: refused, port: "22")
        XCTAssertEqual(failure.kind, .refused)
        XCTAssertEqual(failure.message,
            "Nothing answered on port 22 at this address. Check the address, that the server is on, and that the "
            + "provider firewall allows SSH. If you tried several times, the server may be blocking this Mac for "
            + "a few minutes.")
        XCTAssertEqual(failure.details, refused)
    }

    func testARefusedConnectionNamesThePortTyped() {
        XCTAssertTrue(MachineScanFailure(error: "connect: connection refused", port: "2222").message
            .hasPrefix("Nothing answered on port 2222 at this address."))
    }

    func testATimeoutOrNoRouteSaysTheAddressDidNotAnswer() {
        for error in [
            "dial tcp 203.0.113.20:22: i/o timeout",
            "dial tcp 203.0.113.20:22: connect: no route to host",
            "dial tcp 203.0.113.20:22: connect: network is unreachable",
            "dial tcp 203.0.113.20:22: connect: operation timed out",
            "context deadline exceeded",
        ] {
            let failure = MachineScanFailure(error: error)
            XCTAssertEqual(failure.kind, .noAnswer, error)
            XCTAssertEqual(failure.message, "The address did not answer.", error)
        }
    }

    func testANameThatDoesNotResolveSaysSo() {
        for error in [
            "dial tcp: lookup nowhere.example.com: no such host",
            "dial tcp: lookup nowhere.example.com on 100.64.0.1:53: server misbehaving",
            "could not resolve hostname nowhere.example.com",
        ] {
            let failure = MachineScanFailure(error: error)
            XCTAssertEqual(failure.kind, .unknownName, error)
            XCTAssertEqual(failure.message, "That name does not resolve.", error)
        }
    }

    func testAnythingElseKeepsItsWordsForTheDetails() {
        let failure = MachineScanFailure(error: "devmachine: unknown flag --format")
        XCTAssertEqual(failure.kind, .other)
        XCTAssertEqual(failure.message, "The server's key could not be read.")
        XCTAssertEqual(failure.details, "devmachine: unknown flag --format")
    }
}

final class MachineScanScheduleTests: XCTestCase {
    func testOnlyAnAddressAndAValidPortAreScanned() {
        XCTAssertEqual(MachineScanSchedule.target(address: " 203.0.113.20 ", port: "22"), "203.0.113.20:22")
        XCTAssertNil(MachineScanSchedule.target(address: "", port: "22"))
        XCTAssertNil(MachineScanSchedule.target(address: "203.0.113 .20", port: "22"))
        XCTAssertNil(MachineScanSchedule.target(address: "203.0.113.20", port: "0"))
        XCTAssertNil(MachineScanSchedule.target(address: "203.0.113.20", port: "ssh"))
    }

    func testAnAddressIsScannedOnceUntilItChanges() {
        let target = "203.0.113.20:22"
        XCTAssertTrue(MachineScanSchedule.shouldScan(target: target, scanned: nil, failed: nil))
        XCTAssertFalse(MachineScanSchedule.shouldScan(target: target, scanned: target, failed: nil))
        XCTAssertFalse(MachineScanSchedule.shouldScan(target: target, scanned: nil, failed: target))
        XCTAssertTrue(MachineScanSchedule.shouldScan(target: "203.0.113.21:22", scanned: target, failed: target))
        XCTAssertFalse(MachineScanSchedule.shouldScan(target: nil, scanned: nil, failed: nil))
    }

    func testTheScanWaitsForTypingToPause() {
        XCTAssertGreaterThanOrEqual(MachineScanSchedule.pause, 300_000_000)
        XCTAssertLessThanOrEqual(MachineScanSchedule.pause, 1_500_000_000)
    }
}

final class MachineScanKeyTypeTests: XCTestCase {
    private func scan(_ type: String) -> MachineScan {
        MachineScan(address: "203.0.113.20", port: 22, keyType: type,
                    fingerprint: "SHA256:" + String(repeating: "E", count: 43), verify: nil)
    }

    func testTheKeyTypeReadsAsItsShortName() {
        XCTAssertEqual(scan("ssh-ed25519").keyTypeName, "ED25519")
        XCTAssertEqual(scan("ecdsa-sha2-nistp256").keyTypeName, "ECDSA")
        XCTAssertEqual(scan("ssh-rsa").keyTypeName, "RSA")
        XCTAssertEqual(scan("rsa-sha2-512").keyTypeName, "RSA")
        XCTAssertEqual(scan("ssh-dss").keyTypeName, "SSH-DSS")
    }
}

final class MachineRetryFieldTests: XCTestCase {
    private let keyNotThere = "Error: the key does not log in yet and no password was given: pass the admin "
        + "password on stdin with --password-stdin, or put the key's public half in the admin's authorized_keys first"

    private func addStep(login: ServerLogin) -> MachinePlanStep {
        var draft = MachineDraft()
        draft.name = "backup"
        draft.address = "203.0.113.20"
        draft.keyFile = "~/.ssh/id_ed25519"
        draft.login = login
        return MachinePlan.steps(for: draft, unattended: true)[0]
    }

    private let sync = MachinePlanStep(
        kind: .sync, title: "Install everything on backup", arguments: ["sync", "--machine", "backup", "--yes"],
        asksInTerminal: false)

    func testAKeyThatDoesNotLogInYetAsksForThePasswordInline() {
        XCTAssertEqual(MachineRetryField.field(failedStep: addStep(login: .key), lines: ["…", keyNotThere]), .password)
    }

    func testAPasswordLoginAsksForItAgainSinceItIsNeverKept() {
        XCTAssertEqual(MachineRetryField.field(failedStep: addStep(login: .password), lines: ["refused"]), .password)
    }

    func testAnyOtherFailureAsksForNothing() {
        XCTAssertNil(MachineRetryField.field(failedStep: addStep(login: .key), lines: ["connection refused"]))
        XCTAssertNil(MachineRetryField.field(failedStep: sync, lines: [keyNotThere]))
        XCTAssertNil(MachineRetryField.field(failedStep: nil, lines: [keyNotThere]))
    }

    func testThePanelSaysItInOneSentence() {
        let help = SetupFailureHelp.help(for: addStep(login: .key), lines: [keyNotThere])
        XCTAssertEqual(help.cause, .keyNeedsPassword)
        XCTAssertEqual(help.title, "The key does not log in yet")
        XCTAssertEqual(help.whatToDo, "Type the server's password once to put the key on it.")
        XCTAssertFalse(help.actions.contains(.retry))
    }
}

final class SSHKeyFilesTests: XCTestCase {
    func testOnlyPrivateKeysWithTheirPublicHalfAreOffered() {
        let names = ["config", "known_hosts", "authorized_keys", "id_ed25519", "id_ed25519.pub", "work",
                     "work.pub", "old_rsa", "notes.txt.pub", ".DS_Store"]
        XCTAssertEqual(SSHKeyFiles.privateKeys(names: names), ["~/.ssh/id_ed25519", "~/.ssh/work"])
    }
}
