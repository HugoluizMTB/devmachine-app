import Foundation
import DevmachineCore

@MainActor
final class StatsStore: ObservableObject {
    @Published var snapshot: StatsSnapshot?
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var refreshedAt: Date?

    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func refresh(alias: String) {
        refreshTask?.cancel()
        isLoading = true
        errorText = nil

        refreshTask = Task {
            do {
                let output = try await Task.detached {
                    try RemoteService().run(alias: alias, args: [RemoteCommands.statsSnapshot])
                }.value
                guard !Task.isCancelled else { return }
                self.snapshot = StatsParser.parse(output)
                self.errorText = nil
                self.refreshedAt = Date()
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            if !Task.isCancelled { self.isLoading = false }
        }
    }
}
