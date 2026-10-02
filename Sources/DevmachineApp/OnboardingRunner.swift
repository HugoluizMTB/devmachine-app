import Foundation
import DevmachineCore

/// Where onboarding's programs run. The real one is `TerminalRegistry`;
/// tests stand in for it, so no test starts a shell.
@MainActor
protocol OnboardingPaneLaunching: AnyObject {
    func launch(_ program: PaneProgram, in kind: TerminalKind, onExit: @escaping @MainActor (Int32?) -> Void)
    func close(_ kind: TerminalKind)
}

extension TerminalRegistry: OnboardingPaneLaunching {
    func launch(_ program: PaneProgram, in kind: TerminalKind, onExit: @escaping @MainActor (Int32?) -> Void) {
        runProgram(program, in: kind, onExit: onExit)
        // The person started this run, and `devmachine setup` or the agent
        // waits on their answers: the keyboard goes to the pane once it is up.
        requestFocus(kind)
    }
}

/// Carries out what `OnboardingFlow` decides: starts each step, or the
/// agent, as the program of a fresh pane, and reads the Mac again after
/// each one. A step's exit code is the only thing that ends it, so nothing
/// depends on a shell being ready to take typed text.
@MainActor
final class OnboardingRunner: ObservableObject {
    nonisolated static let sessionPrefix = "devmachine-onboarding"

    @Published private(set) var flow = OnboardingFlow()
    /// The pane on screen: one per step or agent, so an old program's exit
    /// can never be read as the new one's.
    @Published private(set) var paneKind: TerminalKind?

    private let home: String
    private let launcher: any OnboardingPaneLaunching
    private let detect: @Sendable () async -> OnboardingDetection
    private let agentPollInterval: UInt64
    private var paneNumber = 0
    private var detecting = false
    private var detectAgain = false
    private var agentWatch: Task<Void, Never>?

    init(
        home: String = NSHomeDirectory(),
        launcher: (any OnboardingPaneLaunching)? = nil,
        detect: @escaping @Sendable () async -> OnboardingDetection = {
            await Task.detached { OnboardingDetector.detect() }.value
        },
        agentPollInterval: UInt64 = 4_000_000_000
    ) {
        self.home = home
        self.launcher = launcher ?? TerminalRegistry.shared
        self.detect = detect
        self.agentPollInterval = agentPollInterval
    }

    /// Demo screenshots: a flow in any state, with no program behind it.
    func seedDemo(_ flow: OnboardingFlow, paneKind: TerminalKind?) {
        self.flow = flow
        self.paneKind = paneKind
    }

    func start() { perform(flow.start()) }
    func retry() { perform(flow.retry()) }
    func back() { perform(flow.back()) }
    func startAgent(_ kind: AgentKind) { perform(flow.startAgent(kind)) }
    func askAgent(_ kind: AgentKind) { perform(flow.askAgent(kind)) }

    /// The page is going away: whatever still runs in its pane ends with it.
    func leave() {
        agentWatch?.cancel()
        closePane()
    }

    /// Reads the Mac again. Calls that arrive while one is in flight are
    /// folded into a single read after it.
    func refresh() async {
        if detecting {
            detectAgain = true
            return
        }
        detecting = true
        repeat {
            detectAgain = false
            let next = await detect()
            perform(flow.receive(next))
        } while detectAgain
        detecting = false
    }

    private func perform(_ effect: OnboardingEffect?) {
        switch effect {
        case nil:
            break
        case let .runStep(step, command):
            launch(OnboardingPrograms.step(command)) { [weak self] code in
                guard let self else { return }
                perform(flow.stepExited(step, exitCode: code))
            }
        case let .launchAgent(kind, prompt):
            guard let agent = flow.detection.agents.first(where: { $0.kind == kind }) else { return }
            launch(OnboardingPrograms.agent(agent, prompt: prompt)) { [weak self] _ in
                guard let self else { return }
                agentWatch?.cancel()
                perform(flow.agentExited())
            }
            watchAgent()
        case .refreshDetection:
            Task { await refresh() }
        case .stopPane:
            agentWatch?.cancel()
            closePane()
        }
    }

    private func launch(_ program: PaneProgram, onExit: @escaping @MainActor (Int32?) -> Void) {
        closePane()
        paneNumber += 1
        let number = paneNumber
        let kind = TerminalKind.local(session: "\(Self.sessionPrefix)-\(number)", path: home)
        paneKind = kind
        launcher.launch(program, in: kind) { [weak self] code in
            guard let self, number == paneNumber else { return }
            onExit(code)
        }
    }

    private func closePane() {
        guard let kind = paneKind else { return }
        paneKind = nil
        launcher.close(kind)
    }

    /// An agent never says it is done, so the Mac is read every few seconds
    /// while it works; the page moves on by itself once setup is complete.
    private func watchAgent() {
        agentWatch?.cancel()
        let interval = agentPollInterval
        agentWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled, let self else { return }
                guard case .agentRunning = flow.phase else { return }
                await refresh()
            }
        }
    }
}
