import XCTest
@testable import DevmachineCore

final class MachineLocationTests: XCTestCase {
    func testALocationIsTrimmedAndLowerCasedLikeTheCLIDoes() {
        XCTAssertEqual(MachineLocation.normalized("  Hostinger "), "hostinger")
        XCTAssertEqual(MachineLocation.normalized("Other Cloud"), "other cloud")
    }

    func testAValidLocationHasNoProblem() {
        for value in ["home", "hostinger", "other cloud", "rack-2", "eu.west_1", "a"] {
            XCTAssertNil(MachineLocation.problem(value), value)
        }
        XCTAssertNil(MachineLocation.problem("  Home  "))
    }

    func testAnEmptyOrMalformedLocationIsRefused() {
        XCTAssertNotNil(MachineLocation.problem(""))
        XCTAssertNotNil(MachineLocation.problem("   "))
        XCTAssertNotNil(MachineLocation.problem("-home"))
        XCTAssertNotNil(MachineLocation.problem(" .home"))
        XCTAssertNotNil(MachineLocation.problem("home/office"))
        XCTAssertNotNil(MachineLocation.problem("café"))
        XCTAssertNotNil(MachineLocation.problem(String(repeating: "a", count: 41)))
        XCTAssertNil(MachineLocation.problem(String(repeating: "a", count: 40)))
    }

    func testTheDefaultIsExternalForAServerAndLocalForALimaMachine() {
        XCTAssertEqual(MachineLocation.defaultLocation(for: .server), "external")
        XCTAssertEqual(MachineLocation.defaultLocation(for: .localVM), "local")
    }

    func testAReportedLocationWins() {
        XCTAssertEqual(MachineLocation.effective(reported: "Home", isSelf: false, isLocalVM: false), "home")
        XCTAssertEqual(MachineLocation.effective(reported: "hostinger", isSelf: true, isLocalVM: false), "hostinger")
    }

    func testAnOlderCLIThatSaysNothingGivesExternalOrLocal() {
        XCTAssertEqual(MachineLocation.effective(reported: nil, isSelf: false, isLocalVM: false), "external")
        XCTAssertEqual(MachineLocation.effective(reported: nil, isSelf: true, isLocalVM: false), "local")
        XCTAssertEqual(MachineLocation.effective(reported: nil, isSelf: false, isLocalVM: true), "local")
    }

    func testAnEmptyReportIsExternal() {
        XCTAssertEqual(MachineLocation.effective(reported: "  ", isSelf: false, isLocalVM: false), "external")
    }

    func testOnlyAMachineOnThisMacsLoopbackIsALimaMachine() {
        XCTAssertTrue(MachineLocation.isLocalVM(hosts: ["127.0.0.1"], isSelf: false))
        XCTAssertFalse(MachineLocation.isLocalVM(hosts: ["127.0.0.1"], isSelf: true))
        XCTAssertFalse(MachineLocation.isLocalVM(hosts: ["203.0.113.10"], isSelf: false))
        XCTAssertFalse(MachineLocation.isLocalVM(hosts: [], isSelf: false))
        XCTAssertFalse(MachineLocation.isLocalVM(hosts: ["127.0.0.1", "203.0.113.10"], isSelf: false))
    }

    func testTheFlagGoesOnlyToACLIThatTakesIt() {
        let old = SemanticVersion(major: 0, minor: 7, patch: 29)
        let new = SemanticVersion(major: 0, minor: 7, patch: 30)
        XCTAssertFalse(MachineLocation.isSupported(cliVersion: nil))
        XCTAssertFalse(MachineLocation.isSupported(cliVersion: old))
        XCTAssertTrue(MachineLocation.isSupported(cliVersion: new))
        XCTAssertEqual(MachineLocation.flag(" Home ", cliVersion: new), ["--location", "home"])
        XCTAssertEqual(MachineLocation.flag("home", cliVersion: old), [])
        XCTAssertEqual(MachineLocation.flag("", cliVersion: new), [])
    }

    func testEditingALocationIsOneMachinesEdit() {
        XCTAssertEqual(
            MachineLocation.editArguments(machine: "main", location: " Office "),
            ["machines", "edit", "main", "--location", "office", "--yes"])
    }

    func testSuggestionsAreValidLocations() {
        for suggestion in MachineLocation.suggestions {
            XCTAssertNil(MachineLocation.problem(suggestion.value), suggestion.value)
        }
        XCTAssertEqual(MachineLocation.suggestions.map(\.title), ["Hostinger", "Home", "Office", "Other cloud"])
    }

    func testATailnetAddressIsTheCGNATRangeOrATailscaleName() {
        XCTAssertTrue(NetworkAddress.isTailnet("100.64.0.10"))
        XCTAssertTrue(NetworkAddress.isTailnet("100.127.255.1"))
        XCTAssertTrue(NetworkAddress.isTailnet("tailscale:main"))
        XCTAssertFalse(NetworkAddress.isTailnet("100.128.0.1"))
        XCTAssertFalse(NetworkAddress.isTailnet("100.63.0.1"))
        XCTAssertFalse(NetworkAddress.isTailnet("203.0.113.10"))
        XCTAssertFalse(NetworkAddress.isTailnet("main.example.com"))
        XCTAssertFalse(NetworkAddress.isTailnet("100.64.0"))
    }
}

final class MachineLocationPlanTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "B", count: 43)

    private var server: MachineDraft {
        var draft = MachineDraft()
        draft.name = "main"
        draft.address = "203.0.113.10"
        draft.fingerprint = "256 \(fingerprint) root@main (ED25519)"
        draft.keyFile = "~/.ssh/id_ed25519"
        draft.location = "Hostinger"
        return draft
    }

    func testANewDraftIsAnExternalServer() {
        XCTAssertEqual(MachineDraft().location, "external")
    }

    func testAnUnattendedAddPassesTheLocationWhenTheCLITakesIt() {
        let add = MachinePlan.steps(for: server, unattended: true, takesLocation: true).first
        XCTAssertEqual(Array(add?.arguments.suffix(3) ?? []), ["--location", "hostinger", "--yes"])
    }

    func testAnOlderCLIGetsNoLocationFlag() {
        let add = MachinePlan.steps(for: server, unattended: true, takesLocation: false).first
        XCTAssertFalse(add?.arguments.contains("--location") ?? true)
    }

    func testALimaMachineIsCreatedWithItsLocation() {
        var draft = MachineDraft()
        draft.kind = .localVM
        draft.name = "lab"
        draft.location = "local"
        let create = MachinePlan.steps(for: draft, unattended: true, takesLocation: true).first
        XCTAssertEqual(create?.arguments, ["machines", "create-local", "lab", "--add", "--location", "local"])
    }

    func testTheTerminalFlowNeverPassesALocation() {
        let steps = MachinePlan.steps(for: server, unattended: false, takesLocation: true)
        XCTAssertFalse(steps.contains { $0.arguments.contains("--location") })
    }

    func testChoosingAKindPrefillsItsDefaultUnlessOneWasTyped() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, takesLocation: true)
        wizard.choose(.localVM)
        XCTAssertEqual(wizard.draft.location, "local")
        wizard.back()
        wizard.choose(.server)
        XCTAssertEqual(wizard.draft.location, "external")
        wizard.draft.location = "home"
        wizard.back()
        wizard.choose(.localVM)
        XCTAssertEqual(wizard.draft.location, "home")
    }

    func testAnInvalidLocationStopsTheDetails() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, takesLocation: true)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        XCTAssertTrue(wizard.canAdvance)
        wizard.draft.location = "  "
        XCTAssertFalse(wizard.canAdvance)
        XCTAssertEqual(wizard.problems.map(\.field), [.location])
    }

    func testTheSummarySaysWhereAndWhetherItIsKept() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, takesLocation: true)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        XCTAssertEqual(wizard.summary.first { $0.label == "Location" }?.value, "local")
        var older = MachineWizard(existingMachines: [], limaFound: true, unattended: true, takesLocation: false)
        older.choose(.server)
        older.draft.name = "main"
        older.draft.location = "Home"
        XCTAssertEqual(
            older.summary.first { $0.label == "Location" }?.value, "home, kept once the CLI is updated")
    }
}
