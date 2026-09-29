import Foundation
import DevmachineCore

@MainActor
final class CaddyStore: ObservableObject {
    @Published var sites: [CaddySite] = []
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

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        errorText = nil
        let service = self.service

        refreshTask = Task {
            do {
                let sites = try await Task.detached { try service.sites() }.value
                let logs = try await Task.detached { try service.logs() }.value
                guard !Task.isCancelled else { return }
                self.sites = sites
                self.logs = logs
                self.errorText = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = PackageGateMessage.friendly(for: error)
            }
            if !Task.isCancelled { self.isLoading = false }
        }
    }

    func addSubdomain(_ req: SubdomainRequest, workspace: String, settings: AppSettings) {
        addTask?.cancel()
        addError = nil
        let runner: AddSubdomainRunner
        do {
            runner = AddSubdomainRunner(exposer: try DevmachineCLI.resolve(customSocket: settings.sshAgentSocket))
        } catch {
            addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        let taskID = UUID()
        let total = AddSubdomainRunner.stepCount
        task = BGTask(id: taskID, label: "Starting…", completed: 0, total: total)

        addTask = Task {
            let result = await runner.run(workspace: workspace, req) { label, step in
                Task { @MainActor in
                    self.task?.label = label
                    self.task?.completed = step
                }
            }

            switch result {
            case .success:
                self.task?.completed = total
                self.refresh()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.task?.id == taskID { self.task = nil }
            case .failure(let error):
                self.addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.task = nil
            }
        }
    }
}
