import Foundation
import DevmachineCore

/// The first-run setup's states for demo screenshots
/// (`DEVMACHINE_DEMO_WALK=setup-flow`): the flow in a fixed state, the
/// wizard filled in, and the runs seeded with invented logs. Nothing runs.
@MainActor
enum DemoSetupFlow {
    nonisolated static let freshMac = OnboardingDetection(cliFound: false, adminMachine: nil, missingPackageMachines: [])
    nonisolated static let cliInstalled = OnboardingDetection(
        cliFound: true, adminMachine: nil, missingPackageMachines: [], cliVersion: DemoData.unattendedCLI)
    nonisolated static let oldCLI = OnboardingDetection(
        cliFound: true, adminMachine: nil, missingPackageMachines: [],
        cliVersion: SemanticVersion(major: 0, minor: 7, patch: 20))
    nonisolated static let ready = OnboardingDetection(
        cliFound: true, adminMachine: "lab", missingPackageMachines: [], cliVersion: DemoData.unattendedCLI)

    static let screens: [String] = [
        "setup-start", "setup-installing", "setup-install-failed", "setup-choice", "setup-server", "setup-local",
        "setup-packages", "setup-review", "setup-running", "setup-failed", "setup-ready", "setup-cli-old",
    ]

    static func handles(_ id: String) -> Bool { id == "onboarding" || screens.contains(id) }

    static let installLog = [
        "▸ " + CLIInstallPlan.noHomebrewCommand,
        "Downloading devmachine 0.7.30 for darwin/arm64…",
        "Checking its SHA-256…",
    ]

    static let createLog = [
        "▸ Install Lima from github.com/lima-vm/lima into ~/.local, checking its SHA-256",
        "Asking GitHub for Lima's latest release…",
        "Downloading lima-2.2.0-Darwin-arm64.tar.gz and its checksums…",
        "Downloaded 41.3 MB.",
        "SHA-256 matches Lima's SHA256SUMS: 4f1c0d…e7a2",
        "Unpacking into /Users/alice/.local…",
        "limactl version 2.2.0",
        "$ devmachine machines create-local lab --add --cpus 4 --memory 8 --disk 40",
        "Creating lab with Lima (Ubuntu 24.04, 4 CPUs, 8 GiB, 40 GiB)…",
        "INFO[0000] Starting the instance \"lab\" with VM driver \"vz\"",
        "INFO[0003] [hostagent] Waiting for the essential requirement 1 of 2: \"ssh\"",
        "INFO[0021] [hostagent] The essential requirement 1 of 2 is satisfied",
        "INFO[0021] [hostagent] Waiting for the essential requirement 2 of 2: \"user session is ready for ssh\"",
        "INFO[0034] [hostagent] Waiting for cloud-init to finish…",
        "INFO[0058] READY. Run `limactl shell lab` to open the shell.",
        "lab answers on 127.0.0.1 port 60022; its ED25519 key is trusted.",
        "Installing a key with the public password, then proving it…",
        "Password login is now off on lab.",
        "Installing Ansible…",
    ]

    static func seed(_ runner: OnboardingRunner, screen: String) async {
        let wizard = runner.wizard
        switch screen {
        case "setup-installing", "setup-install-failed":
            runner.seedDemo(.demo(detection: freshMac, screen: .preparing, plan: [.installCLI]))
            #if DEBUG
            if screen == "setup-installing" {
                runner.prepare.seedDemo(
                    statuses: [MachinePlanStep.installCLIID: .running], phase: .running, lines: installLog)
            } else {
                runner.prepare.seedDemo(
                    statuses: [MachinePlanStep.installCLIID: .failed], phase: .failed(step: MachinePlanStep.installCLIID),
                    problem: "\(CLIInstallPlan.noHomebrewCommand) ended with an error. The output shows what it said.",
                    lines: [installLog[0], "curl: (6) Could not resolve host: mydevmachine.sh"])
            }
            #endif
        case "setup-ready":
            runner.seedDemo(.demo(detection: ready, screen: .complete))
        case "setup-cli-old":
            runner.seedDemo(.demo(detection: oldCLI, screen: .cliTooOld))
        case "setup-choice", "setup-server", "setup-local", "setup-packages", "setup-review", "setup-running",
             "setup-failed":
            runner.seedDemo(.demo(detection: cliInstalled, screen: .wizard))
            await wizard.prepareFirstRun()
            fill(wizard, screen: screen)
        default:
            runner.seedDemo(.demo(detection: freshMac, screen: .start))
        }
    }

    private static func fill(_ wizard: AddMachineModel, screen: String) {
        switch screen {
        case "setup-choice":
            return
        case "setup-server":
            wizard.wizard.choose(.server)
            wizard.wizard.draft.name = "main"
            wizard.wizard.draft.address = "203.0.113.10"
            wizard.wizard.draft.login = .password
            wizard.wizard.draft.password = SecretText("demo-password")
            wizard.wizard.draft.domain = "example.com"
            wizard.wizard.draft.workspace = "acme"
            wizard.wizard.draft.scan = DemoData.addMachineScan(address: "203.0.113.10", port: "22")
            wizard.wizard.draft.scanConfirmed = true
            return
        default:
            break
        }
        wizard.wizard.choose(.localVM)
        wizard.wizard.draft.name = "lab"
        wizard.wizard.draft.workspace = "acme"
        guard screen != "setup-local" else { return }
        wizard.wizard.next()
        guard screen != "setup-packages" else { return }
        wizard.wizard.next()
        guard screen != "setup-review" else { return }
        wizard.wizard.next()
        #if DEBUG
        let plan = wizard.wizard.plan
        if screen == "setup-running" {
            wizard.runner.seedDemo(
                statuses: [plan[0].id: .done, plan[1].id: .running], phase: .running, lines: createLog)
        } else {
            wizard.runner.seedDemo(
                statuses: [plan[0].id: .failed], phase: .failed(step: plan[0].id),
                problem: "The Internet connection appears to be offline.",
                lines: Array(createLog.prefix(2)) + ["The Internet connection appears to be offline."])
        }
        #endif
    }
}
