import Foundation
import DevmachineCore

@MainActor
final class CaddyStore: ObservableObject {
    @Published var sites: [CaddySite] = []
    /// Port → context user, for hiding what belongs to a workspace turned off.
    @Published var portOwners: [Int: String] = [:]
    @Published var logs: String = ""
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var task: BGTask?
    @Published var addError: String?

    private let service: CaddyService
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?
    private nonisolated(unsafe) var addTask: Task<Void, Never>?

    init(service: CaddyService = CaddyService()) {
        self.service = service
    }

    deinit {
        refreshTask?.cancel()
        addTask?.cancel()
    }

    func refresh(alias: String) {
        refreshTask?.cancel()
        isLoading = true
        errorText = nil
        let service = self.service

        refreshTask = Task {
            do {
                let sites = try await Task.detached { try service.sites(alias: alias) }.value
                let owners = try await Task.detached {
                    (try? service.portOwners(alias: alias)) ?? [:]
                }.value
                let logs = try await Task.detached { try service.logs(alias: alias) }.value
                guard !Task.isCancelled else { return }
                self.sites = sites
                self.portOwners = owners
                self.logs = logs
                self.errorText = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            if !Task.isCancelled { self.isLoading = false }
        }
    }

    func addSubdomain(_ req: SubdomainRequest, settings: AppSettings) {
        addTask?.cancel()
        addError = nil
        let taskID = UUID()
        let total = AddSubdomainRunner.stepCount(for: req)
        task = BGTask(id: taskID, label: "Starting…", completed: 0, total: total)

        let runner = AddSubdomainRunner(settings: settings)
        addTask = Task {
            let result = await runner.run(req) { label, step in
                Task { @MainActor in
                    self.task?.label = label
                    self.task?.completed = step
                }
            }

            switch result {
            case .success:
                self.task?.completed = total
                self.refresh(alias: settings.hostAlias)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.task?.id == taskID { self.task = nil }
            case .failure(let error):
                self.addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.task = nil
            }
        }
    }
}
