import Foundation
import DevmachineCore

/// One step of the guided "set it up here" terminal flow. `installHomebrew`
/// is deliberately not one of these: the app only ever shows its install
/// line (it asks for the Mac password), never runs it. `addPackage`/`sync`
/// carry a machine name since several machines can each be missing the
/// package — one pair of steps per machine, not one pair total.
enum OnboardingStepID: Hashable, Equatable, Sendable {
    case trustTap
    case installCLI
    case runSetup
    case addPackage(machine: String)
    case sync(machine: String)

    var title: String {
        switch self {
        case .trustTap: return "Trust the devmachine tap"
        case .installCLI: return "Install the devmachine CLI"
        case .runSetup: return "Connect a server"
        case let .addPackage(machine): return "Add the devmachine-app package (\(machine))"
        case let .sync(machine): return "Sync \(machine)"
        }
    }

    /// `runSetup` waits on the person's own answers (server address, then a
    /// fingerprint to check with the provider) — shown above the pane so
    /// they know to expect it.
    var interactive: Bool { self == .runSetup }
}

enum OnboardingStepStatus: Equatable, Sendable {
    case waiting
    case running
    case done
    case failed(String)
}

/// One coding agent the "let your agent do it" side can hand the setup to.
enum AgentKind: String, CaseIterable, Equatable, Sendable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var executableName: String { rawValue }

    var knownPaths: [String] {
        ["/opt/homebrew/bin/\(rawValue)", "/usr/local/bin/\(rawValue)", "\(NSHomeDirectory())/.local/bin/\(rawValue)"]
    }
}

struct DetectedAgent: Equatable, Sendable, Identifiable {
    let kind: AgentKind
    let executablePath: String
    var id: AgentKind { kind }
}

/// Resolves a coding agent's executable the same way `GHClient.resolvePath`
/// resolves `gh`: known Homebrew/local-bin paths first, then a login shell's
/// own `command -v` — this catches an nvm/asdf-managed install `gh`'s fixed
/// list would miss.
enum AgentDetector {
    static func detect(
        kinds: [AgentKind] = AgentKind.allCases,
        runner: any CommandRunner = ProcessRunner(),
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> [DetectedAgent] {
        kinds.compactMap { resolve(kind: $0, runner: runner, shell: shell, exists: exists) }
    }

    static func resolve(
        kind: AgentKind,
        runner: any CommandRunner,
        shell: String,
        exists: (String) -> Bool
    ) -> DetectedAgent? {
        if let known = kind.knownPaths.first(where: exists) {
            return DetectedAgent(kind: kind, executablePath: known)
        }
        guard let output = try? runner.run(
            executable: shell, args: ["-lic", "command -v \(kind.executableName)"], environment: nil)
        else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, exists(path) else { return nil }
        return DetectedAgent(kind: kind, executablePath: path)
    }
}

/// The first message handed to an agent asked to do the setup itself.
enum AgentPrompt {
    static let text = "Set up devmachine for me: read https://mydevmachine.sh/agent-setup.md and follow it. "
        + "When the machine is ready, also add the devmachine-app package to it and sync, "
        + "so the Devmachine Mac app works."

    /// The exact command line typed into the terminal — `claude "<prompt>"` /
    /// `codex "<prompt>"`, the initial-prompt form both CLIs accept.
    static func commandLine(for kind: AgentKind) -> String {
        "\(kind.executableName) \(shellQuote(text))"
    }

    static func shellQuote(_ text: String) -> String {
        "\"" + text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
            + "\""
    }
}

/// Everything the onboarding page checks before deciding what to show:
/// Homebrew, the CLI, a configured machine, the `devmachine-app` package on
/// every configured machine, and which agents this Mac has.
struct OnboardingDetection: Equatable, Sendable {
    var homebrewFound: Bool
    var cliFound: Bool
    var adminMachine: String?
    /// Configured (non-self) machines that do not have `devmachine-app` yet —
    /// empty once every machine has it.
    var missingPackageMachines: [String]
    var agents: [DetectedAgent]

    static let empty = OnboardingDetection(
        homebrewFound: false, cliFound: false, adminMachine: nil, missingPackageMachines: [], agents: [])

    var isComplete: Bool { cliFound && adminMachine != nil && missingPackageMachines.isEmpty }
}

enum OnboardingDetector {
    static func detect(
        homebrewPaths: [String] = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        cli: () throws -> DevmachineCLI = { try DevmachineCLI.resolve() },
        agents: () -> [DetectedAgent] = { AgentDetector.detect() }
    ) -> OnboardingDetection {
        let homebrewFound = homebrewPaths.contains(where: exists)
        var cliFound = false
        var adminMachine: String?
        var missingPackageMachines: [String] = []

        if let instance = try? cli() {
            cliFound = true
            adminMachine = try? instance.resolveAdminMachine()
            // Fails open, same as the machine readiness check: a `packages` read that
            // itself fails (offline, too old) leaves nothing "missing" rather
            // than blocking onboarding on a flaky CLI.
            if let machines = try? instance.nonSelfMachines(), !machines.isEmpty,
               let packages = try? instance.packages() {
                let devmachineApp = packages.first { $0.name == "devmachine-app" }
                missingPackageMachines = machines
                    .map(\.name)
                    .filter { !(devmachineApp?.isInstalled(onMachine: $0) ?? false) }
            }
        }

        return OnboardingDetection(
            homebrewFound: homebrewFound, cliFound: cliFound, adminMachine: adminMachine,
            missingPackageMachines: missingPackageMachines, agents: agents())
    }
}

/// The official one-liner from https://brew.sh — shown with a copy button and
/// a link, never run by the app: it asks for the Mac's own password.
enum OnboardingPlan {
    static let homebrewInstallLine =
        #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
    static let trustTapCommand = "brew trust --formula mydevmachine/tap/devmachine"
    static let installCLICommand = "brew install mydevmachine/tap/devmachine"
    static let setupCommand = "devmachine setup"

    static func addPackageCommand(machine: String) -> String {
        "devmachine packages add devmachine-app --machine \(machine)"
    }

    static func syncCommand(machine: String) -> String {
        "devmachine sync --machine \(machine)"
    }

    /// Which steps are still missing, in the order they must run. `machine`
    /// fills in `addPackage`/`sync` when the detected list is empty but the
    /// caller already knows which machine to fix (the package-only gate hands
    /// this in directly, before onboarding re-detects anything itself).
    static func missingSteps(for detection: OnboardingDetection, machine: String? = nil) -> [OnboardingStepID] {
        var steps: [OnboardingStepID] = []
        if !detection.cliFound {
            steps.append(.trustTap)
            steps.append(.installCLI)
        }
        if detection.adminMachine == nil {
            steps.append(.runSetup)
        }
        let machines = detection.missingPackageMachines.isEmpty
            ? [machine].compactMap { $0 }
            : detection.missingPackageMachines
        for machine in machines {
            steps.append(.addPackage(machine: machine))
            steps.append(.sync(machine: machine))
        }
        return steps
    }

    /// The exact command for each missing step, in order.
    static func commands(for detection: OnboardingDetection, machine: String? = nil) -> [(id: OnboardingStepID, command: String)] {
        missingSteps(for: detection, machine: machine).map { id in
            switch id {
            case .trustTap: return (id, trustTapCommand)
            case .installCLI: return (id, installCLICommand)
            case .runSetup: return (id, setupCommand)
            case let .addPackage(machine): return (id, addPackageCommand(machine: machine))
            case let .sync(machine): return (id, syncCommand(machine: machine))
            }
        }
    }
}

/// How the runner tells a step's exit status apart in the terminal's own
/// scrollback, without reading raw bytes off the process itself — some steps
/// (`devmachine setup`) wait on the person's own typed answers, so the
/// terminal is the only thing that knows when they are done.
enum OnboardingMarker {
    static let ok = "__DM_STEP_OK__"
    static let fail = "__DM_STEP_FAIL__"

    static func wrap(_ command: String) -> String {
        "\(command); if [ $? -eq 0 ]; then echo \(ok); else echo \(fail); fi"
    }

    /// Steps run one at a time, so the next marker to appear (by either name)
    /// always belongs to the step that just ran — `stepsFinishedBefore` marks
    /// how many steps before it already finished.
    static func outcome(okCount: Int, failCount: Int, stepsFinishedBefore: Int) -> OnboardingStepStatus? {
        guard okCount + failCount > stepsFinishedBefore else { return nil }
        return okCount > stepsFinishedBefore ? .done : .failed("This step exited with an error. See the terminal above.")
    }
}
