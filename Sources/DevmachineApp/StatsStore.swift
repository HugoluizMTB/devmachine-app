import Foundation
import DevmachineCore

@MainActor
final class StatsStore: ObservableObject {
    @Published var snapshot: StatsSnapshot?
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var refreshedAt: Date?

    private let cli: @Sendable () throws -> DevmachineCLI
    private let adminMachine: AdminMachineCache
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?

    init(
        cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() },
        adminMachine: AdminMachineCache = .shared
    ) {
        self.cli = cli
        self.adminMachine = adminMachine
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        errorText = nil
        let cli = self.cli
        let adminMachine = self.adminMachine

        refreshTask = Task {
            do {
                let output = try await Task.detached {
                    let machine = try adminMachine.name(cli: cli)
                    return try cli().run(machine: machine, command: RemoteCommands.statsSnapshot)
                }.value
                guard !Task.isCancelled else { return }
                guard let parsed = StatsParser.parse(output) else {
                    self.errorText = "The host returned no usable stats."
                    self.isLoading = false
                    return
                }
                self.snapshot = parsed
                self.errorText = nil
                self.refreshedAt = Date()
            } catch {
                guard !Task.isCancelled else { return }
                // The last good snapshot stays on screen, under the error
                // banner: a blip does not have to blank the panel a beta
                // tester was just reading.
                self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            if !Task.isCancelled { self.isLoading = false }
        }
    }
}
