import Foundation
import DevmachineCore

/// Where one machine's host key review stands.
enum HostKeyPhase: Equatable {
    case checking
    /// The key the server presents is not the trusted one: waiting for the
    /// person to compare it on the machine's console.
    case review(HostKeyReport)
    case trusting(HostKeyReport)
    case trusted
    /// The presented key is already the trusted one; ssh failed for another
    /// reason, or the key was fixed in a terminal.
    case matching
    /// The CLI predates `trust --check` reporting a changed key.
    case needsNewerCLI
    case failed(DMErrorState)
}

protocol HostKeyRunning: Sendable {
    func run(_ arguments: [String]) async throws -> CLIOutput
}

/// Runs `devmachine machines trust` off the main thread, with the same ssh
/// agent the rest of the app hands the CLI. It never opens a session: the
/// check reads the server's public key without logging in.
struct ProcessHostKeyRunner: HostKeyRunning {
    var cli: @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }

    func run(_ arguments: [String]) async throws -> CLIOutput {
        let cli = self.cli
        return try await Task.detached {
            let instance = try cli()
            let result = try instance.runner.runCapturing(
                executable: instance.executable, args: arguments, environment: instance.environment())
            return CLIOutput(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
        }.value
    }
}

/// A machine whose SSH host key ssh refused: the check that reads what it
/// presents, and the trust that writes it only after the person pasted the
/// same fingerprint from the machine's own console.
@MainActor
final class HostKeyStore: ObservableObject {
    static let shared = NSClassFromString("XCTestCase") == nil && !DemoMode.isActive
        ? HostKeyStore()
        : HostKeyStore(runner: ProcessHostKeyRunner(cli: {
            throw DevmachineCLIError.commandFailed("no CLI under tests or in demo mode")
        }))

    @Published private(set) var phases: [String: HostKeyPhase] = [:]

    /// The machine's key is trusted again: its workspaces are read again.
    var onTrusted: ((String) -> Void)?

    private let runner: any HostKeyRunning

    init(runner: any HostKeyRunning = ProcessHostKeyRunner()) {
        self.runner = runner
    }

    func phase(for machine: String) -> HostKeyPhase? { phases[machine] }

    func check(_ machine: String) async {
        if case .trusting = phases[machine] { return }
        phases[machine] = .checking
        do {
            let output = try await runner.run(HostKeyTrust.checkArguments(machine: machine))
            phases[machine] = Self.phase(afterCheck: output, machine: machine)
        } catch {
            phases[machine] = .failed(Self.checkFailure(machine: machine, message: Self.describe(error)))
        }
    }

    /// Writes the presented key only when `pasted` holds its exact
    /// fingerprint, and only that key: the CLI refuses with `--expect` if a
    /// second scan meets a different one.
    func trust(_ machine: String, report: HostKeyReport, pasted: String) async {
        guard HostKeyTrust.confirms(pasted, report: report),
              let arguments = HostKeyTrust.trustArguments(for: report) else { return }
        phases[machine] = .trusting(report)
        let task = AppModel.shared?.beginTask(label: "Trusting \(machine)'s host key…", total: 1)
        defer { if let task { AppModel.shared?.finishTask(task) } }
        do {
            let output = try await runner.run(arguments)
            if output.exitCode == 0 {
                phases[machine] = .trusted
                onTrusted?(machine)
            } else {
                phases[machine] = .failed(Self.trustFailure(machine: machine, output: output))
            }
        } catch {
            phases[machine] = .failed(DMErrorState(
                title: "Couldn't trust \(machine)'s host key", message: Self.describe(error)))
        }
    }

    func dismiss(_ machine: String) {
        phases[machine] = nil
    }

    static func phase(afterCheck output: CLIOutput, machine: String) -> HostKeyPhase {
        if output.exitCode == 0, let report = try? HostKeyReport.parse(output.stdout) {
            return report.status == .matching ? .matching : .review(report)
        }
        if HostKeyTrust.isOlderCLIRefusal(output.stderr) { return .needsNewerCLI }
        let message = output.stderr.isEmpty ? output.stdout : output.stderr
        return .failed(checkFailure(machine: machine, message: message))
    }

    private static func checkFailure(machine: String, message: String) -> DMErrorState {
        DMErrorState(title: "Couldn't read \(machine)'s host key", message: message)
    }

    private static func trustFailure(machine: String, output: CLIOutput) -> DMErrorState {
        let message = output.stderr.isEmpty ? output.stdout : output.stderr
        return DMErrorState(
            title: "Couldn't trust \(machine)'s host key",
            cause: message.contains("not the expected")
                ? "The machine presented a different key than the one you checked. Nothing was written."
                : FailureCause(message: message)?.summary,
            details: message)
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
