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

    /// Set only for the website's demo screenshots: a fixed "fresh user"
    /// detection, shown instead of `.task`'s real Homebrew/CLI/machine probe
    /// so the page never depends on what is actually installed.
    var demoDetection: OnboardingDetection?

    @StateObject private var runner = OnboardingRunner()
    @StateObject private var installer: CLIInstallModel
    @State private var detection: OnboardingDetection = .empty
    @State private var path: ChosenPath?
    @State private var didFinish = false

    init(
        initialMachine: String? = nil, onFinished: @escaping () -> Void = {},
        demoDetection: OnboardingDetection? = nil, installer: CLIInstallModel? = nil
    ) {
        self.initialMachine = initialMachine
        self.onFinished = onFinished
        self.demoDetection = demoDetection
        _installer = StateObject(wrappedValue: installer ?? CLIInstallModel())
    }

    private enum ChosenPath: Equatable {
        case terminal
        case agent(AgentKind)
    }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .ambient)
            VStack(alignment: .leading, spacing: m.pt(18)) {
                header
                if !detection.homebrewFound {
                    homebrewBanner
                }
                if path == nil, !detection.cliFound || installer.phase == .installed {
                    installCLICard
                }
                if detection.isComplete {
                    successCard
                } else if let path {
                    runningCard(path)
                } else {
                    chooserCard
                }
            }
            .frame(maxWidth: m.pt(880))
            .padding(m.pt(28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task { await refreshDetection() }
        .onChange(of: runner.statuses) { _, _ in
            Task { await refreshDetection() }
        }
        .onChange(of: installer.phase) { _, phase in
            if phase == .installed { Task { await refreshDetection() } }
        }
        .onChange(of: detection) { _, _ in
            // A step just finished (e.g. `devmachine setup` registered the
            // machine) can change which steps are still missing — pick the
            // newly-appeared ones up without the person pressing Start again.
            if path == .terminal {
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

    // MARK: - Homebrew banner

    private var homebrewBanner: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text("Install Homebrew first")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(.white)
            Text("This asks for your Mac password, so the app shows it instead of running it. "
                + "Paste it into any terminal, then come back here.")
                .font(.dm(11.5))
                .foregroundStyle(.white.opacity(0.65))
            DMCommandBlock(OnboardingPlan.homebrewInstallLine)
            DMButton("brew.sh", variant: .link) {
                NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            }
        }
        .padding(m.space.xl)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    // MARK: - Install the CLI

    private var installCLICard: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: OnboardingInstallContent.title(installer.phase))
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(.white)
            switch installer.phase {
            case .idle:
                Text(verbatim: OnboardingInstallContent.lead(installer.plan))
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                DMButton(OnboardingInstallContent.buttonTitle, systemImage: "arrow.down.circle") {
                    Task { await installer.install() }
                }
                Text(verbatim: OnboardingInstallContent.copyLead)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.55))
                DMCommandBlock(installer.plan.copyCommand)
            case .running:
                ProcessOutputView(lines: installer.output)
            case .installed:
                ProcessOutputView(lines: installer.output)
            case let .failed(error):
                DMErrorStateView(state: error, retry: { Task { await installer.install() } })
                    .frame(maxWidth: .infinity)
                Text(verbatim: OnboardingInstallContent.copyLead)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.55))
                DMCommandBlock(installer.plan.copyCommand)
            }
        }
        .padding(m.space.xl)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    // MARK: - Chooser

    private var chooserCard: some View {
        HStack(alignment: .top, spacing: m.space.xl) {
            VStack(alignment: .leading, spacing: m.pt(10)) {
                Text("Set it up here")
                    .font(.dm(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Runs each missing step in a terminal, one at a time. "
                    + "\"Connect a server\" asks for your server address and shows a "
                    + "fingerprint to check with your provider.")
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: m.space.xs)
                DMButton("Start", systemImage: "play.fill") { startTerminalPath() }
                    .disabled(!detection.homebrewFound)
            }
            .padding(m.space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))

            VStack(alignment: .leading, spacing: m.pt(10)) {
                Text("Let your agent do it")
                    .font(.dm(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Opens the same terminal running your coding agent with the setup prompt. "
                    + "Watch it work and answer what it asks.")
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: m.space.xs)
                ForEach(AgentKind.allCases) { kind in
                    agentButton(kind)
                }
            }
            .padding(m.space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
        }
    }

    private func agentButton(_ kind: AgentKind) -> some View {
        let installed = detection.agents.contains { $0.kind == kind }
        return DMButton(kind.displayName, systemImage: "sparkles", variant: .outline) {
            path = .agent(kind)
            runner.startAgent(kind)
        }
        .disabled(!installed)
        .help(installed ? "" : "\(kind.displayName) is not installed")
    }

    private func startTerminalPath() {
        path = .terminal
        runner.run(steps: currentSteps)
    }

    private var currentSteps: [(id: OnboardingStepID, command: String)] {
        OnboardingPlan.commands(for: detection, machine: initialMachine)
    }

    // MARK: - Running

    private func runningCard(_ path: ChosenPath) -> some View {
        HStack(alignment: .top, spacing: m.space.xl) {
            VStack(spacing: 0) {
                TerminalPaneView(kind: runner.terminalKind)
                    .frame(minHeight: m.pt(360))
            }
            .frame(maxWidth: .infinity)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))

            if case .terminal = path {
                stepList
                    .frame(width: m.pt(260))
            } else {
                VStack(alignment: .leading, spacing: m.space.md) {
                    Text("Answer the agent above.")
                        .font(.dm(12.5, weight: .medium))
                        .foregroundStyle(.white)
                    Text("It reads the setup guide and runs the same commands itself.")
                        .font(.dm(11.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(m.space.xl)
                .frame(width: m.pt(260), alignment: .topLeading)
                .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
            }
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            ForEach(currentSteps, id: \.id) { step in
                stepRow(step)
            }
        }
        .padding(m.space.xl)
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
                DMButton("Retry step", systemImage: "arrow.clockwise", variant: .outline, size: .small) {
                    runner.retry(step: step.id, remaining: currentSteps)
                }
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
