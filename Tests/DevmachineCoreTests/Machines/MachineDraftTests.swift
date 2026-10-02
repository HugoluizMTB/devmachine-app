import XCTest
@testable import DevmachineCore

final class MachineDraftTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "A", count: 43)

    private var server: MachineDraft {
        var draft = MachineDraft()
        draft.kind = .server
        draft.name = "main"
        draft.address = "203.0.113.10"
        draft.fingerprint = fingerprint
        draft.keyFile = "~/.ssh/id_ed25519"
        return draft
    }

    func testAServerWithAKeyAndAFingerprintHasNoProblem() {
        XCTAssertEqual(server.problems(existingMachines: ["backup"]), [])
    }

    func testANameIsRequiredAndMustBeNew() {
        var draft = server
        draft.name = ""
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.name])
        draft.name = "main"
        XCTAssertEqual(draft.problems(existingMachines: ["main"]).map(\.field), [.name])
    }

    func testANameIsLowerCaseLettersDigitsAndDashes() {
        for bad in ["Main", "my box", "-main", "main-", "ma_in", "mäin"] {
            var draft = server
            draft.name = bad
            XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.name], bad)
        }
        var draft = server
        draft.name = "box-2"
        XCTAssertEqual(draft.problems(existingMachines: []), [])
    }

    func testAServerNeedsAnAddressWithoutSpaces() {
        var draft = server
        draft.address = ""
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.address])
        draft.address = "203.0.113.10 "
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.address])
        draft.address = "tailscale:main"
        XCTAssertEqual(draft.problems(existingMachines: []), [])
    }

    func testThePortIsANumberAnSSHServerCanListenOn() {
        for bad in ["", "0", "65536", "22a"] {
            var draft = server
            draft.port = bad
            XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.port], bad)
        }
    }

    func testTheAdminLoginIsALinuxAccountName() {
        var draft = server
        draft.user = "Al ice"
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.user])
        draft.user = "deploy"
        XCTAssertEqual(draft.problems(existingMachines: []), [])
    }

    func testAKeyLoginNeedsTheFingerprintFromTheProvider() {
        var draft = server
        draft.fingerprint = ""
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.fingerprint])
        draft.fingerprint = "SHA256:short"
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.fingerprint])
    }

    func testAKeyLoginNeedsTheKeyTheServerAlreadyTakes() {
        var draft = server
        draft.keyFile = " "
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.keyFile])
        draft.login = .password
        XCTAssertEqual(draft.problems(existingMachines: []), [])
    }

    func testAPasswordLoginLeavesTheFingerprintToTheTerminal() {
        var draft = server
        draft.login = .password
        draft.fingerprint = ""
        XCTAssertEqual(draft.problems(existingMachines: []), [])
    }

    func testTheFingerprintIsReadFromWhatTheConsolePrinted() {
        var draft = server
        draft.fingerprint = "256 \(fingerprint) root@main (ED25519)\n"
        XCTAssertEqual(draft.expectedFingerprint, fingerprint)
        draft.fingerprint = "SHA256:abc"
        XCTAssertNil(draft.expectedFingerprint)
    }

    func testALocalMachineAsksOnlyForAName() {
        var draft = MachineDraft()
        draft.kind = .localVM
        draft.name = "lab"
        XCTAssertEqual(draft.problems(existingMachines: []), [])
    }

    func testAFirstWorkspaceIsOptionalButNamedLikeAMachine() {
        var draft = server
        draft.workspace = ""
        XCTAssertEqual(draft.problems(existingMachines: []), [])
        draft.workspace = "Acme"
        XCTAssertEqual(draft.problems(existingMachines: []).map(\.field), [.workspace])
        draft.workspace = "acme"
        XCTAssertEqual(draft.problems(existingMachines: []), [])
    }
}
