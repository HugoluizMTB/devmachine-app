import XCTest
@testable import DevmachineCore

final class MachineWizardSummaryTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "A", count: 43)

    func testALocalMachineSummarisesItsSizePackagesAndWorkspace() {
        let limits = LocalMachineSizeLimits(cores: 10, memoryBytes: 32 << 30, freeDiskBytes: 400 << 30)
        var wizard = MachineWizard(
            existingMachines: [], limaFound: true, unattended: true, firstRun: true, sizeLimits: limits)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        wizard.draft.localSize = limits.defaultSize
        wizard.draft.packages = ["docker"]
        wizard.draft.workspace = "acme"
        wizard.draft.skillAgents = [SkillAgent(harness: .claude, id: "claude", name: "Claude Code")]

        XCTAssertEqual(wizard.summary, [
            MachineSummaryRow(label: "Machine", value: "lab, a Lima machine on this Mac"),
            MachineSummaryRow(label: "Size", value: "4 CPUs, 8 GiB of memory, a 40 GiB disk"),
            MachineSummaryRow(label: "Packages", value: "essentials, docker, devmachine-app"),
            MachineSummaryRow(label: "Workspace", value: "acme"),
            MachineSummaryRow(label: "Coding agents", value: "Claude Code"),
        ])
        XCTAssertEqual(wizard.previewCommands.first,
                       "devmachine machines create-local lab --add --cpus 4 --memory 8 --disk 40")
    }

    func testAServerSaysWhereAndHowItLogsInAndWhetherItSyncs() {
        var wizard = MachineWizard(existingMachines: ["main"], limaFound: true, unattended: true)
        wizard.choose(.server)
        wizard.draft.name = "backup"
        wizard.draft.address = "203.0.113.20"
        wizard.draft.port = "2222"
        wizard.draft.login = .password
        wizard.draft.fingerprint = fingerprint
        wizard.draft.sync = false

        XCTAssertEqual(wizard.summary, [
            MachineSummaryRow(label: "Machine", value: "backup at 203.0.113.20:2222"),
            MachineSummaryRow(label: "Login", value: "root with a password, used once to install a key"),
            MachineSummaryRow(label: "Packages", value: "essentials"),
            MachineSummaryRow(label: "Workspace", value: "None"),
            MachineSummaryRow(label: "Install now", value: "No: written to the configuration only"),
        ])

        wizard.draft.login = .key
        wizard.draft.keySource = .agent
        XCTAssertEqual(wizard.summary[1].value, "root with a key in the SSH agent")
        wizard.draft.keySource = .file
        wizard.draft.keyFile = "~/.ssh/id_ed25519"
        XCTAssertEqual(wizard.summary[1].value, "root with ~/.ssh/id_ed25519")
    }

    func testNothingIsPreviewedBeforeTheMachineHasAName() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true)
        wizard.choose(.localVM)
        XCTAssertEqual(wizard.summary.first, MachineSummaryRow(label: "Machine", value: "Not named yet"))
        XCTAssertEqual(wizard.previewCommands, [])
    }
}
