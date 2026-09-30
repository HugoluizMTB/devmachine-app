import SwiftUI
import AppKit

/// The guided onboarding flow, shown instead of `CLIGatePage`/`PackageGatePage`
/// while Homebrew, the devmachine CLI, a configured machine, or the
/// `devmachine-app` package are missing. It owns the whole window the same
/// way those gates did — nothing else starts until every check passes.
struct OnboardingPage: View {
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
    @State private var detection: OnboardingDetection = .empty
    @State private var path: ChosenPath?
    @State private var didFinish = false

    private enum ChosenPath: Equatable {
        case terminal
        case agent(AgentKind)
    }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .ambient)
            VStack(alignment: .leading, spacing: 18) {
                header
                if !detection.homebrewFound {
                    homebrewBanner
                }
                if detection.isComplete {
                    successCard
                } else if let path {
                    runningCard(path)
                } else {
                    chooserCard
                }
            }
            .frame(maxWidth: 880)
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task { await refreshDetection() }
        .onChange(of: runner.statuses) { _, _ in
            Task { await refreshDetection() }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up devmachine")
                .font(.dm(20, weight: .semibold))
                .foregroundStyle(.white)
            Text("A few things get this Mac talking to your server. Watch the terminal — nothing runs without you seeing it.")
                .font(.dm(12.5))
                .foregroundStyle(.white.opacity(0.7))
            DMProgressBar(done: progressDone, total: progressTotal, fillColor: .green)
                .frame(maxWidth: 360)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Install Homebrew first")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(.white)
            Text("This asks for your Mac password, so the app shows it instead of running it. "
                + "Paste it into any terminal, then come back here.")
                .font(.dm(11.5))
                .foregroundStyle(.white.opacity(0.65))
            commandRow(OnboardingPlan.homebrewInstallLine)
            DMButton("brew.sh", variant: .link) {
                NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            }
        }
        .padding(16)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    // MARK: - Chooser

    private var chooserCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Set it up here")
                    .font(.dm(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Runs each missing step in a terminal, one at a time. "
                    + "\"Connect a server\" asks for your server address and shows a "
                    + "fingerprint to check with your provider.")
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 4)
                DMButton("Start", systemImage: "play.fill") { startTerminalPath() }
                    .disabled(!detection.homebrewFound)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))

            VStack(alignment: .leading, spacing: 10) {
                Text("Let your agent do it")
                    .font(.dm(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Opens the same terminal running your coding agent with the setup prompt. "
                    + "Watch it work and answer what it asks.")
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 4)
                ForEach(AgentKind.allCases) { kind in
                    agentButton(kind)
                }
            }
            .padding(16)
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
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                TerminalPaneView(kind: runner.terminalKind)
                    .frame(minHeight: 360)
            }
            .frame(maxWidth: .infinity)
            .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))

            if case .terminal = path {
                stepList
                    .frame(width: 260)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer the agent above.")
                        .font(.dm(12.5, weight: .medium))
                        .foregroundStyle(.white)
                    Text("It reads the setup guide and runs the same commands itself.")
                        .font(.dm(11.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(16)
                .frame(width: 260, alignment: .topLeading)
                .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
            }
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(currentSteps, id: \.id) { step in
                stepRow(step)
            }
        }
        .padding(16)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.12))
    }

    private func stepRow(_ step: (id: OnboardingStepID, command: String)) -> some View {
        let status = runner.status(for: step.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Devmachine is ready")
                .font(.dm(16, weight: .semibold))
                .foregroundStyle(.white)
            Text("The CLI, your server, and the devmachine-app package are all set. Restart to load everything.")
                .font(.dm(12.5))
                .foregroundStyle(.white.opacity(0.7))
            DMButton("Restart Devmachine", action: relaunch)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
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

    // MARK: - Small pieces

    private func commandRow(_ command: String) -> some View {
        HStack {
            Text(verbatim: command)
                .font(.dm(11.5, design: .monospaced))
                .foregroundStyle(Color.dmRowText)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            CopyButton(text: command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .dmSurface(Color.dmSelection, radius: DMRadius.control)
    }
}

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        DMButton(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc",
                 variant: .ghost, size: .small) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
    }
}
