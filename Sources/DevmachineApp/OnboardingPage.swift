import SwiftUI
import AppKit

/// The guided onboarding flow, shown instead of `CLIGatePage`/`PackageGatePage`
/// while Homebrew, the devmachine CLI, a configured machine, or the
/// `devmachine-app` package are missing. It owns the whole window the same
/// way those gates did — nothing else starts until every check passes.
struct OnboardingPage: View {
    @Environment(\.dmMetrics) private var m
    /// Known already when onboarding starts from the package-only gate (CLI
    /// present, config present, only the package missing) — the steps list
    /// then skips straight to `addPackage`/`sync`.
    var initialMachine: String? = nil
    var onFinished: () -> Void = {}

    /// Set only for the website's demo screenshots: a fixed detection, and
    /// optionally a run already in some state, shown instead of the real
    /// probe so the page never depends on what is actually installed.
    var demoDetection: OnboardingDetection?
    var demoStatuses: [OnboardingStepID: OnboardingStepStatus]?

    @StateObject private var runner = OnboardingRunner()
    @State private var detection: OnboardingDetection = .empty
    @State private var running = false
    @State private var didFinish = false

    init(
        initialMachine: String? = nil, onFinished: @escaping () -> Void = {},
        demoDetection: OnboardingDetection? = nil,
        demoStatuses: [OnboardingStepID: OnboardingStepStatus]? = nil
    ) {
        self.initialMachine = initialMachine
        self.onFinished = onFinished
        self.demoDetection = demoDetection
        self.demoStatuses = demoStatuses
    }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .ambient)
            VStack(alignment: .leading, spacing: m.pt(18)) {
                header
                if detection.isComplete {
                    successCard
                } else if running {
                    runningCard
                } else {
                    startCard
                }
            }
            .frame(maxWidth: m.pt(880))
            .padding(m.pt(28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task {
            if let demoStatuses {
                running = true
                runner.seedDemo(demoStatuses)
            }
            await refreshDetection()
        }
        .onChange(of: runner.statuses) { _, _ in
            Task { await refreshDetection() }
        }
        .onChange(of: detection) { _, _ in
            // A step just finished (e.g. `devmachine setup` registered the
            // machine) can change which steps are still missing — pick the
            // newly-appeared ones up without the person pressing Start again.
            if running, demoStatuses == nil, failedStep == nil {
                runner.run(steps: currentSteps)
            }
        }
        .onChange(of: detection.isComplete) { _, complete in
            if complete, !didFinish {
                didFinish = true
                onFinished()
            }
        }
    }

    // MARK: - Header / progress

    private var header: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            Text("Set up devmachine")
                .font(.dm(20, weight: .semibold))
                .foregroundStyle(.white)
            Text("A few things get this Mac talking to your server. Watch the terminal — nothing runs without you seeing it.")
                .font(.dm(12.5))
                .foregroundStyle(.white.opacity(0.7))
            DMProgressBar(done: progressDone, total: progressTotal, fillColor: .green)
                .frame(maxWidth: m.pt(360))
        }
    }

    private var progressTotal: Int { 3 }
    private var progressDone: Int {
        var done = 0
        if detection.cliFound { done += 1 }
        if detection.adminMachine != nil { done += 1 }
        if detection.missingPackageMachines.isEmpty { done += 1 }
        return done
    }

    // MARK: - Start

    private var startCard: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text("Installs the devmachine CLI, then connects your server: it asks for "
                + "the server's address and shows a fingerprint to check with your provider. "
                + "No Homebrew or Xcode needed.")
                .font(.dm(12))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            DMButton("Set up devmachine", systemImage: "play.fill", size: .large) { start() }
                .keyboardShortcut(.defaultAction)
            Text("Or run this in a terminal, then `devmachine setup`:")
                .font(.dm(11))
                .foregroundStyle(.white.opacity(0.55))
            DMCommandBlock(OnboardingPlan.installCLICommand)
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    private func start() {
        running = true
        runner.run(steps: currentSteps)
    }

    private func back() {
        runner.reset()
        running = false
    }

    private var currentSteps: [(id: OnboardingStepID, command: String)] {
        OnboardingPlan.commands(for: detection, machine: initialMachine)
    }

    private var failedStep: (id: OnboardingStepID, command: String)? {
        currentSteps.first { step in
            if case .failed = runner.status(for: step.id) { return true }
            return false
        }
    }

    // MARK: - Running

    private var runningCard: some View {
        HStack(alignment: .top, spacing: m.space.xl) {
            VStack(spacing: 0) {
                TerminalPaneView(kind: runner.terminalKind)
                    .frame(minHeight: m.pt(360))
            }
            .frame(maxWidth: .infinity)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))

            VStack(alignment: .leading, spacing: m.space.xl) {
                stepList
                if let failed = failedStep {
                    failureActions(failed)
                }
            }
            .frame(width: m.pt(260))
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            ForEach(currentSteps, id: \.id) { step in
                stepRow(step)
            }
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    private func stepRow(_ step: (id: OnboardingStepID, command: String)) -> some View {
        let status = runner.status(for: step.id)
        return VStack(alignment: .leading, spacing: m.space.xs) {
            HStack(spacing: m.space.md) {
                stepIcon(status)
                Text(step.id.title)
                    .font(.dm(12, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            if case let .failed(message) = status {
                Text(message)
                    .font(.dm(10.5))
                    .foregroundStyle(.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A failed step stops the run: try it again, go back to the start, or
    /// hand it to a coding agent, which can often fix what the CLI cannot —
    /// an outdated Xcode, a missing tool, a network in the way.
    private func failureActions(_ failed: (id: OnboardingStepID, command: String)) -> some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            HStack(spacing: m.space.sm) {
                DMButton("Try again", systemImage: "arrow.clockwise", size: .small) {
                    runner.retry(step: failed.id, remaining: currentSteps)
                }
                DMButton("Back", variant: .outline, size: .small) { back() }
            }
            ForEach(detection.agents) { agent in
                DMButton("Ask \(agent.kind.displayName) to fix it", systemImage: "sparkles",
                         variant: .outline, size: .small) {
                    runner.askAgent(agent.kind, step: failed.id, command: failed.command)
                }
            }
        }
        .padding(m.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
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

    // MARK: - Success

    private var successCard: some View {
        VStack(alignment: .leading, spacing: m.pt(14)) {
            Text("Devmachine is ready")
                .font(.dm(16, weight: .semibold))
                .foregroundStyle(.white)
            Text("The CLI, your server, and the devmachine-app package are all set. Restart to load everything.")
                .font(.dm(12.5))
                .foregroundStyle(.white.opacity(0.7))
            DMButton("Restart Devmachine", action: relaunch)
                .keyboardShortcut(.defaultAction)
        }
        .padding(m.pt(20))
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.14))
    }

    private func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Detection

    private func refreshDetection() async {
        if let demoDetection {
            detection = demoDetection
            return
        }
        let next = await Task.detached { OnboardingDetector.detect() }.value
        detection = next
    }
}
