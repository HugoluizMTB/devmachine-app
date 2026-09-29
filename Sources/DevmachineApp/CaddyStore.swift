import Foundation
import DevmachineCore

@MainActor
final class CaddyStore: ObservableObject {
    @Published var rows: [SubdomainRow] = []
    @Published var domain: String = ""
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var task: BGTask?
    @Published var addError: String?

    @Published var removingHost: String?
    @Published var removeError: String?

    /// Every installed DNS provider, loaded once per page visit — the tab
    /// strip's own list, separate from each tab's records.
    @Published var dnsProviders: [String] = []
    @Published var dnsProvidersError: String?
    @Published var isLoadingDNSProviders = false

    @Published var dnsRecordsByProvider: [String: [DNSRecordRow]] = [:]
    @Published var dnsErrorByProvider: [String: String] = [:]
    @Published var dnsLoadingProviders: Set<String> = []

    private let service: CaddyService
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?
    private nonisolated(unsafe) var addTask: Task<Void, Never>?
    private nonisolated(unsafe) var removeTask: Task<Void, Never>?
    private nonisolated(unsafe) var dnsProvidersTask: Task<Void, Never>?
    private nonisolated(unsafe) var dnsRecordTasks: [String: Task<Void, Never>] = [:]

    init(service: CaddyService = CaddyService()) {
        self.service = service
    }

    deinit {
        refreshTask?.cancel()
        addTask?.cancel()
        removeTask?.cancel()
        dnsProvidersTask?.cancel()
        for task in dnsRecordTasks.values { task.cancel() }
    }

    func refresh() {
        if DemoMode.isActive {
            rows = DemoData.subdomainRows
            domain = DemoData.domain
            dnsProviders = DemoData.dnsProviders
            errorText = nil
            isLoading = false
            return
        }
        refreshTask?.cancel()
        isLoading = true
        errorText = nil
        let service = self.service

        refreshTask = Task {
            do {
                let snapshot = try await Task.detached { try service.snapshot() }.value
                guard !Task.isCancelled else { return }
                self.rows = snapshot.rows
                self.domain = snapshot.domain
                self.errorText = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = PackageGateMessage.friendly(for: error)
            }
            if !Task.isCancelled { self.isLoading = false }
        }
        loadDNSProviders()
    }

    func loadDNSProviders() {
        if DemoMode.isActive {
            dnsProviders = DemoData.dnsProviders
            isLoadingDNSProviders = false
            return
        }
        dnsProvidersTask?.cancel()
        isLoadingDNSProviders = true
        dnsProvidersError = nil
        let service = self.service

        dnsProvidersTask = Task {
            do {
                let names = try await Task.detached { try service.dnsProviderNames() }.value
                guard !Task.isCancelled else { return }
                self.dnsProviders = names
                self.dnsProvidersError = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.dnsProvidersError = PackageGateMessage.friendly(for: error)
            }
            if !Task.isCancelled { self.isLoadingDNSProviders = false }
        }
    }

    /// Loads `provider`'s records for the configured domain, once — a second
    /// call while the first is still running, or already loaded, is a no-op
    /// unless `force`.
    func loadRecords(provider: String, force: Bool = false) {
        if DemoMode.isActive {
            dnsRecordsByProvider[provider] = DemoData.dnsRecordsByProvider[provider] ?? []
            dnsLoadingProviders.remove(provider)
            return
        }
        guard force || (dnsRecordsByProvider[provider] == nil && dnsRecordTasks[provider] == nil) else { return }
        guard !domain.isEmpty else { return }
        dnsRecordTasks[provider]?.cancel()
        dnsLoadingProviders.insert(provider)
        dnsErrorByProvider[provider] = nil
        let service = self.service
        let domain = self.domain

        dnsRecordTasks[provider] = Task {
            do {
                let records = try await Task.detached { try service.dnsRecords(provider: provider, zone: domain) }.value
                guard !Task.isCancelled else { return }
                self.dnsRecordsByProvider[provider] = records
                self.dnsErrorByProvider[provider] = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.dnsErrorByProvider[provider] = PackageGateMessage.friendly(for: error)
            }
            self.dnsLoadingProviders.remove(provider)
            self.dnsRecordTasks[provider] = nil
        }
    }

    func addSubdomain(_ req: SubdomainRequest, workspace: String, settings: AppSettings) {
        guard !DemoMode.isActive else {
            addError = "Demo mode never publishes a real subdomain."
            return
        }
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

    func remove(host: String) {
        removeTask?.cancel()
        removeError = nil
        removingHost = host
        let service = self.service

        removeTask = Task {
            do {
                try await Task.detached { try service.remove(host: host) }.value
                guard !Task.isCancelled else { return }
                self.refresh()
            } catch {
                guard !Task.isCancelled else { return }
                self.removeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            if !Task.isCancelled { self.removingHost = nil }
        }
    }

    /// The Caddy log tail for one host — read on demand for the row's "Logs"
    /// action, not kept around once the popover closes.
    func fetchLogs(host: String) async -> Result<String, Error> {
        let service = self.service
        return await Task.detached { Result { try service.logs(matching: host) } }.value
    }
}
