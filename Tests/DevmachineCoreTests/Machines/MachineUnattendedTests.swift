import XCTest
@testable import DevmachineCore

final class MachineUnattendedGateTests: XCTestCase {
    func testOnlyACLIThatTakesEveryAnswerAsAFlagAddsWithoutATerminal() {
        XCTAssertEqual(MachineUnattendedAdd.minimumCLIVersion, SemanticVersion(major: 0, minor: 7, patch: 27))
        XCTAssertFalse(MachineUnattendedAdd.isSupported(cliVersion: nil))
        XCTAssertFalse(MachineUnattendedAdd.isSupported(cliVersion: SemanticVersion("0.7.26")))
        XCTAssertFalse(MachineUnattendedAdd.isSupported(cliVersion: SemanticVersion("0.7.26-14-g949773c")))
        XCTAssertTrue(MachineUnattendedAdd.isSupported(cliVersion: SemanticVersion("0.7.27")))
        XCTAssertTrue(MachineUnattendedAdd.isSupported(cliVersion: SemanticVersion("0.8.0")))
    }
}

final class MachineScanTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "E", count: 43)

    func testTheScanAsksForJSONAndNamesThePortOnlyWhenItIsNotTheDefault() {
        XCTAssertEqual(
            MachineScan.arguments(address: "203.0.113.20", port: "22"),
            ["--format", "json", "machines", "scan", "--address", "203.0.113.20"])
        XCTAssertEqual(
            MachineScan.arguments(address: " 203.0.113.20 ", port: "2222"),
            ["--format", "json", "machines", "scan", "--address", "203.0.113.20", "--port", "2222"])
    }

    func testTheCLIsAnswerIsRead() throws {
        let scan = try XCTUnwrap(MachineScan.parse(#"""
            {"address":"203.0.113.20","port":22,"key_type":"ssh-ed25519","fingerprint":"\#(fingerprint)",
             "verify":"ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"}
            """#))
        XCTAssertEqual(scan.address, "203.0.113.20")
        XCTAssertEqual(scan.port, 22)
        XCTAssertEqual(scan.keyType, "ssh-ed25519")
        XCTAssertEqual(scan.fingerprint, fingerprint)
        XCTAssertEqual(scan.verify, "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
    }

    func testAKeyTypeWithNoStandardFileHasNoVerifyCommand() throws {
        let scan = try XCTUnwrap(MachineScan.parse(
            #"{"address":"203.0.113.20","port":22,"key_type":"ssh-dss","fingerprint":"\#(fingerprint)"}"#))
        XCTAssertNil(scan.verify)
    }

    func testAnAnswerWithNoUsableFingerprintIsNoScan() {
        XCTAssertNil(MachineScan.parse("not json"))
        XCTAssertNil(MachineScan.parse(#"{"address":"203.0.113.20","port":22,"key_type":"ssh-ed25519","fingerprint":"md5:aa"}"#))
    }
}

final class AgentKeyListTests: XCTestCase {
    private let first = "SHA256:" + String(repeating: "F", count: 43)
    private let second = "SHA256:" + String(repeating: "G", count: 43)

    func testEachKeyTheAgentHoldsIsRead() {
        let keys = AgentKeyList.parse("""
            256 \(first) alice@example.com (ED25519)
            4096 \(second) Work key with spaces (RSA)

            """)
        XCTAssertEqual(keys, [
            AgentKey(fingerprint: first, comment: "alice@example.com", type: "ED25519"),
            AgentKey(fingerprint: second, comment: "Work key with spaces", type: "RSA"),
        ])
        XCTAssertEqual(keys[0].keyArgument, "agent:\(first)")
    }

    func testAnEmptyAgentHoldsNoKey() {
        XCTAssertEqual(AgentKeyList.parse("The agent has no identities.\n"), [])
        XCTAssertEqual(AgentKeyList.parse(""), [])
    }

    func testTheAgentIsAskedToListOnlyFingerprints() {
        XCTAssertEqual(AgentKeyList.arguments, ["-l", "-E", "sha256"])
    }
}

final class MachinePlanUnattendedTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "H", count: 43)
    private let scanned = "SHA256:" + String(repeating: "J", count: 43)

    private var server: MachineDraft {
        var draft = MachineDraft()
        draft.name = "backup"
        draft.address = "203.0.113.20"
        draft.fingerprint = "256 \(fingerprint) root@backup (ED25519)"
        draft.keyFile = "~/.ssh/id_ed25519"
        return draft
    }

    private func scan(_ fingerprint: String, address: String = "203.0.113.20", port: Int = 22) -> MachineScan {
        MachineScan(address: address, port: port, keyType: "ssh-ed25519", fingerprint: fingerprint,
                    verify: "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
    }

    func testAPasswordServerIsAddedWithItsPasswordOnStdinAndNoTerminal() {
        var draft = server
        draft.login = .password
        draft.password = SecretText("hunter2 with spaces")
        let add = MachinePlan.steps(for: draft, unattended: true)[0]
        XCTAssertEqual(add.arguments, [
            "machines", "add", "--name", "backup", "--address", "203.0.113.20",
            "--fingerprint", fingerprint, "--password-stdin", "--yes",
        ])
        XCTAssertEqual(add.input, .password)
        XCTAssertFalse(add.asksInTerminal)
        XCTAssertFalse(add.displayLine.contains("hunter2"))
        XCTAssertFalse(add.id.contains("hunter2"))
        XCTAssertEqual(MachinePlan.terminalAnswers(for: draft, unattended: true), [])
    }

    func testTheSamePasswordServerOnAnOlderCLIStillGoesThroughItsQuestions() {
        var draft = server
        draft.login = .password
        draft.password = SecretText("hunter2")
        let add = MachinePlan.steps(for: draft, unattended: false)[0]
        XCTAssertEqual(add.arguments, ["machines", "add", "--yes"])
        XCTAssertTrue(add.asksInTerminal)
        XCTAssertNil(add.input)
    }

    func testAKeyTheAgentHoldsIsNamedByItsFingerprint() {
        var draft = server
        draft.keySource = .agent
        draft.agentKey = scanned
        XCTAssertEqual(MachinePlan.steps(for: draft, unattended: true)[0].arguments, [
            "machines", "add", "--name", "backup", "--address", "203.0.113.20",
            "--fingerprint", fingerprint, "--key", "agent:\(scanned)", "--yes",
        ])
    }

    func testTheFirstMachineIsAddedWithoutSetupAndCarriesTheDomain() {
        var draft = server
        draft.hasConfiguration = false
        draft.domain = " example.com "
        draft.essentials = false
        let add = MachinePlan.steps(for: draft, unattended: true)[0]
        XCTAssertEqual(add.arguments, [
            "machines", "add", "--name", "backup", "--address", "203.0.113.20",
            "--fingerprint", fingerprint, "--key", "~/.ssh/id_ed25519", "--domain", "example.com",
            "--no-essentials", "--yes",
        ])
        XCTAssertFalse(add.asksInTerminal)
    }

    func testADomainIsNeverPassedOnceAConfigurationExists() {
        var draft = server
        draft.domain = "example.com"
        XCTAssertFalse(MachinePlan.steps(for: draft, unattended: true)[0].arguments.contains("--domain"))
    }

    func testALocalMachineIsCreatedAndAddedInOneCommand() {
        var draft = MachineDraft()
        draft.kind = .localVM
        draft.name = "lab"
        draft.essentials = false
        draft.workspace = "acme-lab"
        let steps = MachinePlan.steps(for: draft, unattended: true)
        XCTAssertEqual(steps.map(\.arguments), [
            ["machines", "create-local", "lab", "--add", "--no-essentials"],
            ["workspaces", "new", "acme-lab", "--machine", "lab", "--yes"],
            ["sync", "--machine", "lab", "--yes"],
        ])
        XCTAssertEqual(steps.map(\.asksInTerminal), [false, false, false])
        XCTAssertEqual(steps.first?.kind, .createLocal)
    }

    func testAConfirmedScanIsTheFingerprintTrusted() {
        var draft = server
        draft.fingerprint = ""
        draft.scan = scan(scanned)
        XCTAssertNil(draft.fingerprintToTrust)
        draft.scanConfirmed = true
        XCTAssertEqual(draft.fingerprintToTrust, scanned)
        XCTAssertEqual(MachinePlan.steps(for: draft, unattended: true)[0].arguments[7], scanned)
    }

    func testPastedConsoleOutputHoldingTheScannedKeyConfirmsIt() {
        var draft = server
        draft.scan = scan(fingerprint)
        XCTAssertEqual(draft.fingerprintToTrust, fingerprint)
        XCTAssertTrue(draft.consoleConfirmsScan)
    }

    func testAConsoleThatDisagreesWithTheScanTrustsNothing() {
        var draft = server
        draft.scan = scan(scanned)
        draft.scanConfirmed = true
        XCTAssertNil(draft.fingerprintToTrust)
        XCTAssertTrue(draft.problems(existingMachines: [], unattended: true).contains {
            $0.field == .fingerprint && $0.message.contains("different key")
        })
    }

    func testAScanOfAnotherAddressOrPortCountsForNothing() {
        var draft = server
        draft.fingerprint = ""
        draft.scan = scan(scanned)
        draft.scanConfirmed = true
        draft.port = "2222"
        XCTAssertNil(draft.currentScan)
        XCTAssertNil(draft.fingerprintToTrust)
        draft.port = "22"
        draft.address = "203.0.113.21"
        XCTAssertNil(draft.currentScan)
    }

    func testAPasswordLoginNeedsThePasswordAndAFingerprint() {
        var draft = server
        draft.login = .password
        draft.fingerprint = ""
        let problems = draft.problems(existingMachines: [], unattended: true)
        XCTAssertTrue(problems.contains { $0.field == .password })
        XCTAssertTrue(problems.contains { $0.field == .fingerprint })
        XCTAssertFalse(problems.contains { $0.field == .keyFile })

        draft.password = SecretText("hunter2")
        draft.fingerprint = fingerprint
        XCTAssertEqual(draft.problems(existingMachines: [], unattended: true), [])
    }

    func testAnAgentKeyHasToBeChosen() {
        var draft = server
        draft.keyFile = ""
        draft.keySource = .agent
        XCTAssertEqual(draft.problems(existingMachines: [], unattended: true).map(\.field), [.agentKey])
        draft.agentKey = scanned
        XCTAssertEqual(draft.problems(existingMachines: [], unattended: true), [])
    }

    func testATypedDomainHasToLookLikeOne() {
        var draft = server
        draft.hasConfiguration = false
        draft.domain = "not a domain"
        XCTAssertEqual(draft.problems(existingMachines: [], unattended: true).map(\.field), [.domain])
        draft.domain = ""
        XCTAssertEqual(draft.problems(existingMachines: [], unattended: true), [])
    }

    func testThePasswordNeverShowsWhenTheDraftIsPrinted() {
        var draft = server
        draft.password = SecretText("hunter2")
        XCTAssertFalse(String(describing: draft).contains("hunter2"))
        XCTAssertFalse(String(reflecting: draft).contains("hunter2"))
        XCTAssertEqual(draft.password.value, "hunter2")
    }
}

final class MachinePackagePlatformTests: XCTestCase {
    func testAMacOnlyPackageIsNeverOfferedForALinuxMachine() {
        let cards = MachinePackageCatalog.cards(from: [
            PackageInfo(name: "docker", scope: "machine", summary: "Docker.", source: "release", platforms: ["linux"]),
            PackageInfo(name: "brew-tools", scope: "machine", summary: "Homebrew.", source: "release",
                        platforms: ["macos"]),
            PackageInfo(name: "tailscale", scope: "machine", summary: "Tailnet.", source: "release", platforms: []),
            PackageInfo(name: "both", scope: "machine", summary: "Both.", source: "release",
                        platforms: ["linux", "macos"]),
        ], platform: MachinePackageCatalog.linux)
        XCTAssertEqual(cards.map(\.name), ["both", "docker", "tailscale"])
    }

    func testEssentialsSaysWhatItContains() {
        let cards = MachinePackageCatalog.cards(from: [
            PackageInfo(name: "essentials", scope: "machine", summary: "Most machines want it.", source: "release",
                        needs: ["base", "git", "firewall"]),
            PackageInfo(name: "docker", scope: "machine", summary: "Docker.", source: "release", needs: ["base"]),
        ], platform: MachinePackageCatalog.linux)
        XCTAssertEqual(cards[0].contains, ["base", "git", "firewall"])
        XCTAssertEqual(cards[1].contains, [])
    }
}
