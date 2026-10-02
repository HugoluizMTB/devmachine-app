import SwiftUI
import AppKit

/// The first-run setup. It owns the whole window until the Mac is ready or
/// the person skips it: one button runs every step (CLI, `devmachine setup`,
/// the devmachine-app package and its sync), or a detected agent does the
/// same from a prompt. It ends on a button into the app, never on a restart.
struct OnboardingPage: View {
    @Environment(\.dmMetrics) private var m

    var onStart: () -> Void = {}
    var onSkip: () -> Void = {}

    /// Set only for demo screenshots: the flow in a fixed state, and the pane
    /// whose demo transcript stands in for a program.
    var demoFlow: OnboardingFlow?
    var demoPaneKind: TerminalKind?

    @StateObject private var runner = OnboardingRunner()

    init(
        onStart: @escaping () -> Void = {}, onSkip: @escaping () -> Void = {},
        demoFlow: OnboardingFlow? = nil, demoPaneKind: TerminalKind? = nil
    ) {
        self.onStart = onStart
        self.onSkip = onSkip
        self.demoFlow = demoFlow
        self.demoPaneKind = demoPaneKind
    }

    private var flow: OnboardingFlow { runner.flow }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .ambient)
            VStack(alignment: .leading, spacing: m.pt(18)) {
                header
                content
            }
            .frame(maxWidth: usesPane ? m.pt(1180) : m.pt(720))
            .padding(m.pt(28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task {
            if let demoFlow {
                runner.seedDemo(demoFlow, paneKind: demoPaneKind)
                return
            }
            await runner.refresh()
        }
        .onDisappear { runner.leave() }
    }

    private var usesPane: Bool {
        switch flow.phase {
        case .start, .complete: return false
        default: return true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .start:
            startCard
        case .complete:
            successCard
        case .running, .checking, .failed:
            withPane { stepList; stepActions }
        case let .agentRunning(kind):
            withPane { agentCard(kind, running: true) }
        case let .agentStopped(kind):
            withPane { agentCard(kind, running: false) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            Text(flow.phase == .complete ? "You are all set" : "Set up devmachine")
                .font(.dm(20, weight: .semibold))
                .foregroundStyle(.white)
            Text("This Mac needs the devmachine CLI, a server it can reach, and the devmachine-app "
                + "package on that server. Everything runs in a terminal you can watch.")
                .font(.dm(12.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            DMProgressBar(done: stagesDone, total: stages.count, fillColor: .green)
                .frame(maxWidth: m.pt(360))
        }
    }

    private struct Stage: Identifiable {
        let title: String
        let done: Bool
        var id: String { title }
    }

    private var stages: [Stage] {
        let detection = flow.detection
        return [
            Stage(title: "The devmachine CLI is installed", done: detection.cliFound),
            Stage(title: "A server is connected", done: detection.adminMachine != nil),
            Stage(
                title: "Every server has devmachine-app",
                done: detection.adminMachine != nil && detection.missingPackageMachines.isEmpty),
        ]
    }

    private var stagesDone: Int {
        flow.phase == .complete ? stages.count : stages.filter(\.done).count
    }

    // MARK: - Start

    private var startCard: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text("One button does it all: it installs the CLI (no Homebrew or Xcode needed), "
                + "then connects your server. That step asks for the server's address and shows a "
                + "fingerprint to check with your provider. Then it adds devmachine-app to the server.")
                .font(.dm(12))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: m.space.md) {
                DMButton("Set up devmachine", systemImage: "play.fill", size: .large,
                         isLoading: !flow.hasDetected) { runner.start() }
                    .keyboardShortcut(.defaultAction)
                ForEach(flow.detection.agents) { agent in
                    DMButton("Let \(agent.kind.displayName) do it", systemImage: "sparkles",
                             variant: .outline, size: .large) { runner.startAgent(agent.kind) }
                }
            }
            if !flow.detection.agents.isEmpty {
                Text("The agent starts with a prompt to follow mydevmachine.sh/agent-setup.md and add "
                    + "devmachine-app. You answer it in the terminal; this page moves on when the setup is complete.")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: m.space.md) {
                DMButton("Skip for now", variant: .ghost, size: .small) { skip() }
                Text("Sessions on this Mac work without a server. Settings can run the setup later.")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, m.space.md)
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    private func skip() {
        runner.leave()
        onSkip()
    }

    // MARK: - Pane and steps

    private func withPane<Side: View>(@ViewBuilder side: () -> Side) -> some View {
        HStack(alignment: .top, spacing: m.space.xl) {
            pane
            VStack(alignment: .leading, spacing: m.space.xl) {
                side()
            }
            .frame(width: m.pt(300))
        }
    }

    private var pane: some View {
        VStack(spacing: 0) {
            if let kind = runner.paneKind {
                TerminalPaneView(kind: kind)
                    .id(kind)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: m.pt(380), maxHeight: m.pt(560))
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            ForEach(flow.steps, id: \.self) { step in
                stepRow(step)
            }
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    private func stepRow(_ step: OnboardingStepID) -> some View {
        let status = flow.status(of: step)
        return VStack(alignment: .leading, spacing: m.space.xs) {
            HStack(spacing: m.space.md) {
                stepIcon(status)
                Text(step.title)
                    .font(.dm(12, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            if status == .running, step.interactive {
                Text("Answer its questions in the terminal.")
                    .font(.dm(10.5))
                    .foregroundStyle(.white.opacity(0.6))
            }
            if case let .failed(message) = status {
                Text(message)
                    .font(.dm(10.5))
                    .foregroundStyle(.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func stepIcon(_ status: OnboardingStepStatus) -> some View {
        switch status {
        case .waiting:
            Image(systemName: "circle")
                .foregroundStyle(.white.opacity(0.35))
        case .running:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    /// A failed step stops the run: try it again, go back, or hand it to a
    /// coding agent. While a step runs, Back stops it.
    @ViewBuilder
    private var stepActions: some View {
        if case .failed = flow.phase {
            VStack(alignment: .leading, spacing: m.space.md) {
                HStack(spacing: m.space.sm) {
                    DMButton("Try again", systemImage: "arrow.clockwise", size: .small) { runner.retry() }
                        .keyboardShortcut(.defaultAction)
                    DMButton("Back", variant: .outline, size: .small) { runner.back() }
                }
                ForEach(flow.detection.agents) { agent in
                    DMButton("Ask \(agent.kind.displayName) to fix it", systemImage: "sparkles",
                             variant: .outline, size: .small) { runner.askAgent(agent.kind) }
                }
            }
            .padding(m.space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
        } else {
            DMButton("Stop and go back", variant: .ghost, size: .small) { runner.back() }
        }
    }

    // MARK: - Agent

    private func agentCard(_ kind: AgentKind, running: Bool) -> some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(running
                 ? "\(kind.displayName) is setting things up"
                 : "\(kind.displayName) stopped before the setup finished")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(running
                 ? "Answer it in the terminal. This page moves on by itself once everything below is done."
                 : "Pick up from where it stopped: the button runs only the steps still missing.")
                .font(.dm(11.5))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: m.pt(8)) {
                ForEach(stages) { stage in
                    HStack(spacing: m.space.md) {
                        stepIcon(stage.done ? .done : (running ? .running : .waiting))
                        Text(stage.title)
                            .font(.dm(11.5))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            if running {
                DMButton("Stop and go back", variant: .ghost, size: .small) { runner.back() }
            } else {
                VStack(alignment: .leading, spacing: m.space.sm) {
                    DMButton("Set up devmachine", systemImage: "play.fill", size: .small) { runner.start() }
                        .keyboardShortcut(.defaultAction)
                    HStack(spacing: m.space.sm) {
                        DMButton("Open \(kind.displayName) again", systemImage: "sparkles",
                                 variant: .outline, size: .small) { runner.startAgent(kind) }
                        DMButton("Back", variant: .outline, size: .small) { runner.back() }
                    }
                }
            }
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    // MARK: - Success

    private var successCard: some View {
        VStack(alignment: .leading, spacing: m.pt(14)) {
            HStack(spacing: m.space.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.dm(22))
                    .foregroundStyle(.green)
                Text("Devmachine is ready")
                    .font(.dm(16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(readySummary)
                .font(.dm(12.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            DMButton("Start using Devmachine", systemImage: "arrow.right", size: .large) {
                runner.leave()
                onStart()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(m.pt(20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.14))
    }

    private var readySummary: String {
        let server = flow.detection.adminMachine.map { "the server \($0)" } ?? "your server"
        return "The CLI is installed, and \(server) has devmachine-app. "
            + "Settings are filled in from the CLI, so there is nothing to type."
    }
}
