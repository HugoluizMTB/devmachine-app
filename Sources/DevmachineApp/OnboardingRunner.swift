import Foundation
import AppKit
import DevmachineCore

/// Drives the "set it up here" side of onboarding: types each missing step's
/// command into the shared embedded local terminal, one after another, and
/// watches the pane's own scrollback for the `OnboardingMarker` this step's
/// command appends, since a step like `devmachine setup` waits on the
/// person's own answers and there is no other way to know it is done.
@MainActor
final class OnboardingRunner: ObservableObject {
    static let sessionName = "devmachine-onboarding"

    @Published private(set) var statuses: [OnboardingStepID: OnboardingStepStatus] = [:]
    @Published private(set) var currentStep: OnboardingStepID?

    let terminalKind: TerminalKind

    private let sender: any SessionCommandSending
    private let matchCounter: (String, TerminalKind) -> Int
    private let pollInterval: UInt64
    private var runToken = UUID()

    init(
        path: String = NSHomeDirectory(),
        sender: any SessionCommandSending = HostRunner(),
        matchCounter: @escaping (String, TerminalKind) -> Int = { term, kind in
            TerminalRegistry.shared.matchCount(term, in: kind)
        },
        pollInterval: UInt64 = 500_000_000
    ) {
        self.terminalKind = .local(session: Self.sessionName, path: path)
        self.sender = sender
        self.matchCounter = matchCounter
        self.pollInterval = pollInterval
    }

    func status(for id: OnboardingStepID) -> OnboardingStepStatus {
        statuses[id] ?? .waiting
    }

    /// Runs every step in `steps` that has not already finished, in order,
    /// stopping at the first failure. Steps already `.done` (a retry after a
    /// later failure) are skipped.
    func run(steps: [(id: OnboardingStepID, command: String)]) {
        let token = UUID()
        runToken = token
        Task { await runSequentially(steps, token: token) }
    }

    /// Forgets every step and stops whatever was waiting: the page's Back.
    func reset() {
        runToken = UUID()
        statuses = [:]
        currentStep = nil
    }

    /// Demo screenshots: a run in any state, without a terminal.
    func seedDemo(_ statuses: [OnboardingStepID: OnboardingStepStatus]) {
        self.statuses = statuses
    }

    /// Re-runs one failed step and, if it succeeds, continues with the rest
    /// of `steps` from that point on.
    func retry(step: OnboardingStepID, remaining: [(id: OnboardingStepID, command: String)]) {
        statuses[step] = .waiting
        run(steps: remaining)
    }

    private func runSequentially(_ steps: [(id: OnboardingStepID, command: String)], token: UUID) async {
        var stepsFinishedBefore = steps.prefix { statuses[$0.id] == .done }.count
        for step in steps[stepsFinishedBefore...] {
            guard runToken == token else { return }
            await runOne(step, token: token)
            guard runToken == token else { return }
            if case .failed = statuses[step.id] { return }
            stepsFinishedBefore += 1
        }
    }

    private func runOne(_ step: (id: OnboardingStepID, command: String), token: UUID) async {
        currentStep = step.id
        statuses[step.id] = .running
        let nonce = OnboardingMarker.newNonce()
        do {
            try sender.send(OnboardingMarker.wrap(step.command, nonce: nonce), into: CommandTarget.from(terminalKind))
        } catch {
            statuses[step.id] = .failed(error.localizedDescription)
            return
        }
        await waitForOutcome(step.id, nonce: nonce, token: token)
    }

    private func waitForOutcome(_ id: OnboardingStepID, nonce: String, token: UUID) async {
        while runToken == token {
            if let outcome = OnboardingMarker.outcome(
                okSeen: matchCounter(OnboardingMarker.ok(nonce: nonce), terminalKind) > 0,
                failSeen: matchCounter(OnboardingMarker.fail(nonce: nonce), terminalKind) > 0) {
                statuses[id] = outcome
                return
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
    }

    /// Opens a coding agent on a failed step, in the same terminal, which is
    /// back at its prompt once a step has failed. It gets the step and the
    /// exact command, and runs it again itself to see the error.
    func askAgent(_ kind: AgentKind, step: OnboardingStepID, command: String) {
        let line = AgentPrompt.helpCommandLine(for: kind, step: step, command: command)
        try? sender.send(line, into: CommandTarget.from(terminalKind))
    }
}

private extension CommandTarget {
    static func from(_ kind: TerminalKind) -> CommandTarget {
        switch kind {
        case let .remote(alias, session): return .remote(alias: alias, session: session)
        case let .local(session, path): return .local(session: session, path: path)
        }
    }
}
