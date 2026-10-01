import Foundation
import DevmachineCore

protocol CLIInstallRunning: Sendable {
    func run(_ plan: CLIInstallPlan, output: @escaping @Sendable (String) -> Void) async throws -> Int32
}

/// Runs the install in the background, never in a terminal session. stdin is
/// closed, so anything that would ask for a password fails instead of waiting.
struct ProcessCLIInstallRunner: CLIInstallRunning {
    var environment: [String: String] = ProcessInfo.processInfo.environment

    func run(_ plan: CLIInstallPlan, output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        try await StreamingProcess.run(
            executable: plan.executable, arguments: plan.arguments,
            environment: CLISelfUpdate.environment(base: environment), output: output)
    }
}

enum CLIInstallPhase: Equatable {
    case idle
    case running
    case installed
    case failed(DMErrorState)
}

/// Onboarding's Install CLI button: Homebrew when this Mac has it, else the
/// project's installer, with the log streamed as it runs. Success is what the
/// app itself can find afterwards, not the exit code alone.
@MainActor
final class CLIInstallModel: ObservableObject {
    @Published private(set) var phase: CLIInstallPhase = .idle
    @Published private(set) var output: [String] = []

    let plan: CLIInstallPlan
    private let runner: any CLIInstallRunning
    private let findsCLI: @Sendable () async -> Bool

    init(
        plan: CLIInstallPlan = CLIInstallPlan.choose(exists: { FileManager.default.isExecutableFile(atPath: $0) }),
        runner: any CLIInstallRunning = ProcessCLIInstallRunner(),
        findsCLI: @escaping @Sendable () async -> Bool = { (try? DevmachineCLI.resolve()) != nil }
    ) {
        self.plan = plan
        self.runner = runner
        self.findsCLI = findsCLI
    }

    func install() async {
        guard phase != .running else { return }
        output = []
        phase = .running
        let sink = ProcessOutputSink { [weak self] lines in
            if (self?.output.count ?? 0) < lines.count { self?.output = lines }
        }
        sink.receive("$ " + plan.copyCommand)
        do {
            let status = try await runner.run(plan, output: sink.receive)
            output = sink.snapshot
            guard status == 0 else {
                phase = .failed(failure(fallback: "The install exited with status \(status)."))
                return
            }
        } catch {
            output = sink.snapshot
            phase = .failed(failure(fallback: error.localizedDescription))
            return
        }
        guard await findsCLI() else {
            phase = .failed(DMErrorState(
                title: "The CLI was installed, but the app can't find it",
                cause: "It looks in /opt/homebrew/bin, /usr/local/bin and ~/.local/bin.",
                details: output.joined(separator: "\n")))
            return
        }
        phase = .installed
    }

    private func failure(fallback: String) -> DMErrorState {
        let cause = MachinePrepare.failureCause(output)
            ?? output.last(where: { $0.hasPrefix("devmachine install:") })
            ?? FailureCause(message: output.joined(separator: "\n"))?.summary
            ?? fallback
        return DMErrorState(
            title: "The CLI was not installed", cause: cause,
            details: output.isEmpty ? fallback : output.joined(separator: "\n"))
    }

    #if DEBUG
    func seedDemo(phase: CLIInstallPhase, output: [String]) {
        self.phase = phase
        self.output = output
    }
    #endif
}

/// The Install CLI card's words, kept apart from the view so they are tested.
enum OnboardingInstallContent {
    static let buttonTitle = "Install CLI"
    static let copyLead = "Or run this in a terminal:"

    static func title(_ phase: CLIInstallPhase) -> String {
        switch phase {
        case .idle, .failed: return "Install the devmachine CLI"
        case .running: return "Installing the devmachine CLI…"
        case .installed: return "The devmachine CLI is installed"
        }
    }

    static func lead(_ plan: CLIInstallPlan) -> String {
        switch plan {
        case .homebrew:
            return "The app installs it with Homebrew, in the background. Nothing is typed into a terminal."
        case .installer:
            return "The app runs the devmachine installer in the background. It puts the CLI in "
                + "~/.local/bin and needs no password."
        }
    }
}
