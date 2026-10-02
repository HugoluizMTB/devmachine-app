import Foundation

/// Why a step did not get the Mac further.
enum OnboardingFailure: Equatable, Sendable {
    /// The step's program ended with this exit code, or nil for a signal.
    case exited(Int32?)
    /// It exited 0, yet the Mac reads the same as before it ran: running it
    /// again blindly would loop forever, so it stops here instead.
    case unresolved
    /// Demo mode shows the flow and runs nothing.
    case demo

    func message(for step: OnboardingStepID) -> String {
        switch self {
        case let .exited(code?):
            return "It stopped with exit code \(code). The terminal shows why."
        case .exited(nil):
            return "It was stopped before it finished."
        case .demo:
            return "Demo mode never runs a step."
        case .unresolved:
            switch step {
            case .installCLI: return "It finished, but the app still cannot find the devmachine CLI."
            case .runSetup: return "It finished, but no server is configured yet."
            case let .addPackage(machine): return "It finished, but \(machine) still has no devmachine-app package."
            case let .sync(machine): return "It finished, but \(machine) still does not have devmachine-app."
            }
        }
    }
}

enum OnboardingPhase: Equatable, Sendable {
    case start
    case running(OnboardingStepID)
    /// The step exited 0; the Mac is being read again to pick the next one.
    case checking(OnboardingStepID)
    case failed(OnboardingStepID, OnboardingFailure)
    case agentRunning(AgentKind)
    /// The agent's program ended before the Mac was ready.
    case agentStopped(AgentKind)
    case complete
}

/// What the runner has to do after an event: the flow itself never touches a
/// terminal or the CLI, so every path through it is a plain unit test.
enum OnboardingEffect: Equatable, Sendable {
    case runStep(OnboardingStepID, command: String)
    case refreshDetection
    case launchAgent(AgentKind, prompt: String)
    case stopPane
}

/// The setup flow as a state machine. Each step is a program of its own and
/// ends with an exit code, so a step always ends in done or failed; a step
/// that exits 0 without changing what the Mac reports is a failure too.
/// Every failure waits for the person: Try again, Back or an agent.
struct OnboardingFlow: Equatable, Sendable {
    private(set) var phase: OnboardingPhase = .start
    private(set) var detection: OnboardingDetection = .empty
    private(set) var hasDetected = false
    /// Steps that exited 0 in this run, in the order they ran.
    private(set) var finished: [OnboardingStepID] = []

    /// What is still to run. A sync follows every package added in this run
    /// even when the package already reads as there: the CLI lists a
    /// package as soon as it is declared, before any sync applied it.
    var pending: [OnboardingStepID] {
        var list = OnboardingPlan.missingSteps(for: detection).filter { !finished.contains($0) }
        for case let .addPackage(machine) in finished
        where !finished.contains(.sync(machine: machine)) && !list.contains(.sync(machine: machine)) {
            list.append(.sync(machine: machine))
        }
        return list
    }

    var isReady: Bool { detection.isComplete && pending.isEmpty }

    /// The list the page shows: what ran, then what is left.
    var steps: [OnboardingStepID] { finished + pending }

    func status(of step: OnboardingStepID) -> OnboardingStepStatus {
        switch phase {
        case let .running(current) where current == step,
             let .checking(current) where current == step:
            return .running
        case let .failed(current, failure) where current == step:
            return .failed(failure.message(for: step))
        default:
            return finished.contains(step) ? .done : .waiting
        }
    }

    mutating func receive(_ next: OnboardingDetection) -> OnboardingEffect? {
        detection = next
        hasDetected = true
        switch phase {
        case .running, .complete:
            return nil
        case let .checking(step):
            return afterCheck(step)
        case .start, .failed, .agentRunning, .agentStopped:
            if isReady { phase = .complete }
            return nil
        }
    }

    private mutating func afterCheck(_ step: OnboardingStepID) -> OnboardingEffect? {
        let stillMissing = OnboardingPlan.missingSteps(for: detection).contains(step)
        let expectedUntilSync = { if case .addPackage = step { return true } else { return false } }()
        if stillMissing && !expectedUntilSync {
            return fail(step, .unresolved)
        }
        if isReady {
            phase = .complete
            return nil
        }
        guard let next = pending.first else { return fail(step, .unresolved) }
        return run(next)
    }

    private mutating func fail(_ step: OnboardingStepID, _ failure: OnboardingFailure) -> OnboardingEffect? {
        finished.removeAll { $0 == step }
        phase = .failed(step, failure)
        return nil
    }

    private mutating func run(_ step: OnboardingStepID) -> OnboardingEffect {
        phase = .running(step)
        return .runStep(step, command: OnboardingPlan.command(for: step))
    }

    /// The one "Set up devmachine" button, also offered after an agent quit.
    mutating func start() -> OnboardingEffect? {
        guard hasDetected else { return nil }
        switch phase {
        case .start, .agentStopped:
            if isReady {
                phase = .complete
                return nil
            }
            return pending.first.map { run($0) }
        default:
            return nil
        }
    }

    mutating func stepExited(_ step: OnboardingStepID, exitCode: Int32?) -> OnboardingEffect? {
        guard phase == .running(step) else { return nil }
        guard exitCode == 0 else { return fail(step, .exited(exitCode)) }
        finished.append(step)
        phase = .checking(step)
        return .refreshDetection
    }

    /// The step could not be started at all (demo mode).
    mutating func refuse(_ step: OnboardingStepID) -> OnboardingEffect? {
        guard phase == .running(step) else { return nil }
        return fail(step, .demo)
    }

    mutating func retry() -> OnboardingEffect? {
        guard case let .failed(step, _) = phase else { return nil }
        return run(step)
    }

    mutating func back() -> OnboardingEffect? {
        phase = .start
        finished = []
        return .stopPane
    }

    mutating func startAgent(_ kind: AgentKind) -> OnboardingEffect? {
        guard hasAgent(kind) else { return nil }
        switch phase {
        case .start, .agentStopped:
            phase = .agentRunning(kind)
            return .launchAgent(kind, prompt: AgentPrompt.setup)
        default:
            return nil
        }
    }

    /// Hands a failed step to an agent, which can often fix what the CLI
    /// cannot: an outdated tool, a network in the way.
    mutating func askAgent(_ kind: AgentKind) -> OnboardingEffect? {
        guard hasAgent(kind), case let .failed(step, _) = phase else { return nil }
        phase = .agentRunning(kind)
        return .launchAgent(kind, prompt: AgentPrompt.help(step: step, command: OnboardingPlan.command(for: step)))
    }

    mutating func agentExited() -> OnboardingEffect? {
        guard case let .agentRunning(kind) = phase else { return nil }
        phase = .agentStopped(kind)
        return .refreshDetection
    }

    private func hasAgent(_ kind: AgentKind) -> Bool {
        detection.agents.contains { $0.kind == kind }
    }

    /// Demo screenshots only: a flow already in a given state.
    static func demo(
        detection: OnboardingDetection, phase: OnboardingPhase, finished: [OnboardingStepID] = []
    ) -> OnboardingFlow {
        var flow = OnboardingFlow()
        flow.detection = detection
        flow.hasDetected = true
        flow.phase = phase
        flow.finished = finished
        return flow
    }
}

/// A program a pane runs instead of a shell, with the arguments it gets
/// as they are: nothing is typed into a shell that may still be starting.
struct PaneProgram: Equatable, Sendable {
    let executable: String
    let args: [String]
    let environment: [String]
}

enum OnboardingPrograms {
    /// A pipe fails when any part of it fails: `curl … | sh` with curl
    /// unable to reach the server would otherwise exit 0.
    static let pipefail = "setopt pipefail; "

    /// oh-my-zsh asks whether to update when a shell starts, and that
    /// question would take the step's terminal before the step does.
    static let environment = ["DISABLE_AUTO_UPDATE=true", "DISABLE_UPDATE_PROMPT=true"]

    /// zsh as a login, interactive shell: the same PATH, ssh agent and
    /// variables a Terminal window has, which the CLI and its ssh need.
    static func step(_ command: String) -> PaneProgram {
        PaneProgram(
            executable: "/bin/zsh", args: ["-l", "-i", "-c", pipefail + command], environment: environment)
    }

    /// The agent is the pane's program, with the prompt as its argument. Its
    /// own folder goes first on PATH (an npm install needs its `node`), and
    /// `~/.local/bin` too, where the CLI it installs lands.
    static func agent(_ agent: DetectedAgent, prompt: String) -> PaneProgram {
        PaneProgram(
            executable: "/bin/zsh",
            args: [
                "-l", "-i", "-c",
                #"export PATH="${1:h}:$HOME/.local/bin:$PATH"; exec "$1" "$2""#,
                "devmachine-setup", agent.executablePath, prompt,
            ],
            environment: environment)
    }
}
