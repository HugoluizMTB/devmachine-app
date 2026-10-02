import Foundation

/// The setup flow's states for demo screenshots (`DEVMACHINE_DEMO_WALK=setup-flow`):
/// each is an `OnboardingFlow` in a fixed state and a demo pane whose name
/// picks its transcript (`DemoData.onboardingTranscript`). Nothing runs.
enum DemoSetupFlow {
    static let agents = [
        DetectedAgent(kind: .claude, executablePath: "/opt/homebrew/bin/claude"),
        DetectedAgent(kind: .codex, executablePath: "/opt/homebrew/bin/codex"),
    ]

    static let freshMac = OnboardingDetection(
        cliFound: false, adminMachine: nil, missingPackageMachines: [], agents: agents)
    static let cliInstalled = OnboardingDetection(
        cliFound: true, adminMachine: nil, missingPackageMachines: [], agents: agents)
    static let ready = OnboardingDetection(
        cliFound: true, adminMachine: "main", missingPackageMachines: [], agents: agents)

    static func pane(_ name: String) -> TerminalKind {
        .local(session: "\(OnboardingRunner.sessionPrefix)-demo-\(name)", path: "/Users/alice")
    }

    /// The flow and its pane for one screen id, or nil for an id that is
    /// not a setup screen.
    static func state(for id: String) -> (flow: OnboardingFlow, pane: TerminalKind?)? {
        switch id {
        case "onboarding", "setup-start", "install-cli":
            return (.demo(detection: freshMac, phase: .start), nil)
        case "setup-running":
            return (.demo(detection: cliInstalled, phase: .running(.runSetup), finished: [.installCLI]),
                    pane("setup"))
        case "install-cli-running":
            return (.demo(detection: freshMac, phase: .running(.installCLI)), pane("install"))
        case "setup-failed", "install-cli-failed":
            return (.demo(detection: freshMac, phase: .failed(.installCLI, .exited(6))), pane("failed"))
        case "setup-agent":
            return (.demo(detection: cliInstalled, phase: .agentRunning(.claude)), pane("agent"))
        case "setup-agent-stopped":
            return (.demo(detection: cliInstalled, phase: .agentStopped(.claude)), pane("agent"))
        case "setup-ready":
            return (.demo(
                detection: ready, phase: .complete,
                finished: [.installCLI, .runSetup, .addPackage(machine: "main"), .sync(machine: "main")]), nil)
        default:
            return nil
        }
    }
}
