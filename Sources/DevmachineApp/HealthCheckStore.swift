import Foundation
import DevmachineCore

/// `devmachine doctor`'s result for one configured machine — the self
/// machine (`devmachine machine doctor`) or a remote one
/// (`devmachine doctor --machine <name>`).
struct MachineHealth: Identifiable, Equatable, Sendable {
    let id: String
    let machineName: String
    let isSelf: Bool
    var checks: [DoctorCheck] = []
    var rawOutput: String?
    var errorText: String?
}

@MainActor
final class HealthCheckStore: ObservableObject {
    @Published var results: [MachineHealth] = []
    @Published var isRunning = false
    @Published var lastRunAt: Date?
    /// Set only when the CLI itself could not be reached at all — listing
    /// machines failed, or the binary is missing. A machine-specific failure
    /// stays on that machine's row instead.
    @Published var commandErrorText: String?

    private let cli: @Sendable () throws -> DevmachineCLI
    private nonisolated(unsafe) var runTask: Task<Void, Never>?

    init(cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }) {
        self.cli = cli
    }

    deinit {
        runTask?.cancel()
    }

    func run() {
        if DemoMode.isActive {
            results = DemoData.machineHealth
            lastRunAt = Date()
            isRunning = false
            commandErrorText = nil
            return
        }
        runTask?.cancel()
        isRunning = true
        commandErrorText = nil
        let cli = self.cli

        runTask = Task {
            do {
                let machines = try await Task.detached { try cli().listMachines() }.value
                guard !Task.isCancelled else { return }

                var health: [MachineHealth] = []
                for machine in machines {
                    guard !Task.isCancelled else { return }
                    health.append(await Self.check(machine: machine, cli: cli))
                }
                self.results = health
                self.lastRunAt = Date()
            } catch {
                guard !Task.isCancelled else { return }
                self.commandErrorText = PackageGateMessage.friendly(for: error)
            }
            if !Task.isCancelled { self.isRunning = false }
        }
    }

    private static func check(machine: CLIMachine, cli: @escaping @Sendable () throws -> DevmachineCLI) async -> MachineHealth {
        var health = MachineHealth(id: machine.name, machineName: machine.name, isSelf: machine.isSelf)
        do {
            let outcome = try await Task.detached {
                machine.isSelf ? try cli().machineDoctor() : try cli().doctor(machine: machine.name)
            }.value
            switch outcome {
            case let .report(report):
                health.checks = report.checks
            case let .raw(text):
                health.rawOutput = text
            }
        } catch {
            health.errorText = PackageGateMessage.friendly(for: error)
        }
        return health
    }
}
