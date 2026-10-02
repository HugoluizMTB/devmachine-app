import Foundation
import DevmachineCore

enum OnboardingScreen: Equatable, Sendable {
    case start
    /// Steps outside the wizard run in the background (`OnboardingPlan`).
    case preparing
    /// The CLI is older than the wizard needs.
    case cliTooOld
    /// The Add machine wizard, in its first-run form.
    case wizard
    case complete
}

/// What the runner has to do after an event: the flow itself never starts
/// a process or reads the CLI, so every path through it is a plain unit test.
enum OnboardingEffect: Equatable, Sendable {
    case run([MachinePlanStep])
    case openWizard
    case refreshDetection
    case stop
}

/// The first-run setup as a state machine: the CLI is installed, then the
/// Add machine wizard sets up the first machine, then the Mac is read again.
/// A run that fails stays on screen for Retry, which `MachineStepRunner`
/// resumes from the failed step. A run that ends well but leaves the Mac as
/// it was is a failure too (`unresolved`), never run again in a loop.
struct OnboardingFlow: Equatable, Sendable {
    private(set) var screen: OnboardingScreen = .start
    private(set) var detection: OnboardingDetection = .empty
    private(set) var hasDetected = false
    /// The steps of the run on screen.
    private(set) var plan: [MachinePlanStep] = []
    /// It finished, yet the Mac reads the same: what to tell the person.
    private(set) var unresolved: String?
    private var checking = false

    var isReady: Bool { detection.isComplete }

    mutating func receive(_ next: OnboardingDetection) -> OnboardingEffect? {
        detection = next
        hasDetected = true
        guard checking else {
            if screen == .start, isReady { screen = .complete }
            if screen == .cliTooOld, detection.addsWithoutTerminal { return advance() }
            return nil
        }
        checking = false
        if screen == .preparing, OnboardingPlan.prepareSteps(for: detection) == plan, !isReady {
            unresolved = Self.unresolvedMessage(plan)
            return nil
        }
        if screen == .wizard, detection.adminMachine == nil {
            unresolved = "The machine was set up, but the CLI does not list it yet. Check again, or go back and run it again."
            return nil
        }
        return advance()
    }

    /// The one "Set up devmachine" button.
    mutating func start() -> OnboardingEffect? {
        guard hasDetected, screen == .start else { return nil }
        return advance()
    }

    /// The run on screen ended. A failure waits for Retry or Back.
    mutating func runFinished(succeeded: Bool) -> OnboardingEffect? {
        guard screen == .preparing, succeeded else { return nil }
        checking = true
        return .refreshDetection
    }

    /// The wizard's run added the machine.
    mutating func wizardFinished() -> OnboardingEffect? {
        guard screen == .wizard else { return nil }
        checking = true
        return .refreshDetection
    }

    /// Retry after `unresolved`: the Mac is read again, then the next step runs.
    mutating func checkAgain() -> OnboardingEffect? {
        guard unresolved != nil || screen == .cliTooOld else { return nil }
        unresolved = nil
        checking = true
        if screen == .cliTooOld { checking = false }
        return .refreshDetection
    }

    /// The CLI is too old: install the latest over it.
    mutating func updateCLI() -> OnboardingEffect? {
        guard screen == .cliTooOld else { return nil }
        return run([.installCLI])
    }

    mutating func back() -> OnboardingEffect? {
        screen = .start
        plan = []
        unresolved = nil
        checking = false
        return .stop
    }

    private mutating func advance() -> OnboardingEffect? {
        unresolved = nil
        if isReady {
            screen = .complete
            return nil
        }
        if !detection.cliFound { return run([.installCLI]) }
        if !detection.addsWithoutTerminal {
            screen = .cliTooOld
            return nil
        }
        if detection.adminMachine == nil {
            screen = .wizard
            plan = []
            return .openWizard
        }
        return run(OnboardingPlan.prepareSteps(for: detection))
    }

    private mutating func run(_ steps: [MachinePlanStep]) -> OnboardingEffect {
        screen = .preparing
        plan = steps
        return .run(steps)
    }

    private static func unresolvedMessage(_ plan: [MachinePlanStep]) -> String {
        if plan.first?.kind == .installCLI {
            return "The installer finished, but the app still cannot find the devmachine CLI in ~/.local/bin, "
                + "/opt/homebrew/bin or /usr/local/bin."
        }
        return "It finished, but a machine still does not list devmachine-app."
    }

    /// Demo screenshots only: a flow already in a given state.
    static func demo(
        detection: OnboardingDetection, screen: OnboardingScreen, plan: [MachinePlanStep] = [],
        unresolved: String? = nil
    ) -> OnboardingFlow {
        var flow = OnboardingFlow()
        flow.detection = detection
        flow.hasDetected = true
        flow.screen = screen
        flow.plan = plan
        flow.unresolved = unresolved
        return flow
    }
}
