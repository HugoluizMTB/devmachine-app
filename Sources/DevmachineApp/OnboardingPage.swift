import SwiftUI
import AppKit
import DevmachineCore

/// The first-run setup. It owns the whole window until the Mac is ready or
/// the person skips it: the CLI is installed, then the Add machine wizard
/// sets up the first machine (a server, or one on this Mac), every step a
/// `devmachine` command with its log on screen. It ends on a button into the
/// app, never on a restart.
struct OnboardingPage: View {
    @Environment(\.dmMetrics) private var m

    var onStart: () -> Void = {}
    var onSkip: () -> Void = {}

    /// Set only for demo screenshots: the flow in a fixed state, and how to
    /// fill the wizard and the runs for it.
    var demoScreen: String?

    @StateObject private var runner = OnboardingRunner()

    init(onStart: @escaping () -> Void = {}, onSkip: @escaping () -> Void = {}, demoScreen: String? = nil) {
        self.onStart = onStart
        self.onSkip = onSkip
        self.demoScreen = demoScreen
    }

    private var flow: OnboardingFlow { runner.flow }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .ambient)
            VStack(alignment: .leading, spacing: m.pt(18)) {
                header
                content
            }
            .frame(maxWidth: isWide ? m.pt(1180) : m.pt(720))
            .padding(m.pt(28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task {
            if let demoScreen {
                await DemoSetupFlow.seed(runner, screen: demoScreen)
                return
            }
            await runner.refresh()
        }
        .onDisappear { runner.leave() }
    }

    private var isWide: Bool {
        flow.screen == .preparing || flow.screen == .wizard || (flow.screen == .complete && !runner.isAllSet)
    }

    @ViewBuilder
    private var content: some View {
        switch flow.screen {
        case .start: startCard
        case .preparing: preparing
        case .cliTooOld: cliTooOld
        case .wizard: wizard
        case .complete:
            if runner.isAllSet { successCard } else { preparing }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            Text(runner.isAllSet ? "You are all set" : "Set up devmachine")
                .font(.dm(20, weight: .semibold))
                .foregroundStyle(.white)
            Text("This Mac needs the devmachine CLI and one machine: a server you have, or a virtual machine "
                + "on this Mac. Every step is a devmachine command, and its log shows as it runs.")
                .font(.dm(12.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            DMProgressBar(done: stagesDone, total: 4, fillColor: .green)
                .frame(maxWidth: m.pt(360))
        }
    }

    private var stagesDone: Int {
        guard !runner.isAllSet else { return 4 }
        let detection = flow.detection
        return [detection.cliFound, detection.adminMachine != nil, detection.isComplete].filter { $0 }.count
    }

    // MARK: - Start

    private var startCard: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text("First it installs the devmachine CLI (no Homebrew or Xcode needed). Then it asks whether you "
                + "already have a server. No server? It makes a machine on this Mac instead. You see every "
                + "command before it runs.")
                .font(.dm(12))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            DMButton("Set up devmachine", systemImage: "play.fill", size: .large,
                     isLoading: !flow.hasDetected) { runner.start() }
                .keyboardShortcut(.defaultAction)
            HStack(spacing: m.space.md) {
                DMButton("Skip for now", variant: .ghost, size: .small) { skip() }
                Text("Sessions on this Mac work without a machine. Settings can run the setup later.")
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

    // MARK: - Steps outside the wizard

    private var preparing: some View {
        OnboardingPrepareView(runner: runner, prepare: runner.prepare)
            .padding(m.space.xl)
            .frame(maxWidth: .infinity, minHeight: m.pt(420), maxHeight: m.pt(600), alignment: .topLeading)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    private var cliTooOld: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: "This devmachine CLI is too old for the setup")
                .font(.dm(14, weight: .semibold))
                .foregroundStyle(.white)
            Text(verbatim: OnboardingContent.cliTooOld(flow.detection.cliVersion))
                .font(.dm(12))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            DMCommandBlock(CLIInstallPlan.noHomebrewCommand, wraps: true)
            HStack(spacing: m.space.sm) {
                DMButton("Install the latest CLI", systemImage: "arrow.down.circle", size: .small) { runner.updateCLI() }
                    .keyboardShortcut(.defaultAction)
                DMButton("Check again", variant: .outline, size: .small) { runner.checkAgain() }
                DMButton("Back", variant: .outline, size: .small) { runner.back() }
            }
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    // MARK: - Wizard

    private var wizard: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            if let unresolved = flow.unresolved {
                DMErrorStateView(
                    state: DMErrorState(title: "The machine does not show yet", cause: unresolved, details: unresolved),
                    retry: { runner.checkAgain() }, retryTitle: "Check again")
            }
            AddMachineWizardView(
                state: runner.wizard, title: "Your first machine", cards: runner.wizard.packageCards,
                onClose: { runner.back() })
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, minHeight: m.pt(480), maxHeight: m.pt(680), alignment: .topLeading)
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
            Text(OnboardingContent.ready(flow.detection.adminMachine, workspace: runner.wizard.madeWorkspace))
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
}

enum OnboardingContent {
    static func cliTooOld(_ version: SemanticVersion?) -> String {
        let installed = version.map { "You have \($0). " } ?? ""
        return installed + "The setup needs \(MachineUnattendedAdd.minimumCLIVersion) or newer, which takes every "
            + "answer as a flag. Install the latest below. If a Homebrew copy of devmachine is older, update it "
            + "with brew upgrade devmachine, since it is found first."
    }

    static func ready(_ machine: String?, workspace: String? = nil) -> String {
        let server = machine.map { "the machine \($0)" } ?? "your machine"
        let sidebar = workspace.map { " Your workspace \($0) is in the sidebar: start a session there." } ?? ""
        return "The CLI is installed, the packages release is downloaded, and \(server) answers with "
            + "devmachine-app." + sidebar
            + " Settings are filled in from the CLI, so there is nothing to type."
    }
}

/// The CLI install (or the package on a machine set up before) running
/// with its log, and how it ended.
private struct OnboardingPrepareView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var runner: OnboardingRunner
    @ObservedObject var prepare: MachineStepRunner

    private var failedStep: MachinePlanStep? {
        runner.flow.plan.first { prepare.status(of: $0) == .failed }
    }

    var body: some View {
        MachineRunLayout(steps: runner.flow.plan, runner: prepare) {
            if let unresolved = runner.flow.unresolved {
                DMErrorStateView(
                    state: DMErrorState(title: "It finished, but nothing changed", cause: unresolved,
                                        details: prepare.lines.suffix(30).joined(separator: "\n")),
                    retry: { runner.checkAgain() }, retryTitle: "Check again")
                DMButton("Back", systemImage: "chevron.left", variant: .outline, size: .small) { runner.back() }
            } else if case .failed = prepare.phase {
                SetupFailurePanel(
                    step: failedStep, lines: prepare.lines, problem: prepare.problem, exitCode: prepare.exitCode,
                    onRetry: { runner.retry() })
                DMButton("Back", systemImage: "chevron.left", variant: .outline, size: .small) { runner.back() }
            } else {
                Text(verbatim: "Each step's log shows on the left as it runs.")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMButton("Stop and go back", systemImage: "stop.fill", variant: .outline, size: .small) {
                    runner.back()
                }
            }
        }
    }
}
