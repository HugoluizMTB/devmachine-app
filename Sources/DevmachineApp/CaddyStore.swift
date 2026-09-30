import Foundation
import DevmachineCore

/// What one DNS provider tab has to show.
enum DNSRecordsPhase: Equatable {
    case skeleton
    case failed(String)
    case loaded([DNSRecordRow])
}

/// One machine's sites, loading flag and error — kept per machine so one
/// that cannot be reached never blanks, or blocks, another's list.
struct MachineSitesState: Equatable, Sendable {
    var rows: [SubdomainRow] = []
    var hasLoaded = false
    var isLoading = false
    var errorText: String?
    /// Set for a machine with nothing to publish from (this Mac, or a server
    /// without caddy): a plain explanation in place of a raw CLI error.
    var notSetUpMessage: String?
}

/// Remembers which machine the Subdomains page last showed, across
/// launches. A per-viewer convenience, never a source of truth about which
/// machines exist.
final class SitesMachineSelection: @unchecked Sendable {
    private static let key = "CaddyStore.selectedMachine"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var machineName: String? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

@MainActor
final class CaddyStore: ObservableObject {
    static let noDomainMessage = "No domain is configured, so there is no zone to read records from."

    @Published private(set) var machines: [CLIMachine] = []
    @Published private(set) var selectedMachine: String?
    @Published private(set) var sitesByMachine: [String: MachineSitesState] = [:]
    @Published private(set) var isLoadingMachines = false
    @Published private(set) var machinesError: String?
    @Published var domain: String = ""
    @Published var task: BGTask?
    @Published var addError: String?

    @Published var removingHost: String?
    @Published var removeError: String?

    /// The selected server's installed DNS providers — the tab strip's own
    /// list, separate from each tab's records.
    @Published var dnsProviders: [String] = []
    @Published var dnsProvidersError: String?
    @Published var isLoadingDNSProviders = false

    @Published var dnsRecordsByProvider: [String: [DNSRecordRow]] = [:]
    @Published var dnsErrorByProvider: [String: String] = [:]
    @Published var dnsLoadingProviders: Set<String> = []

    private var context = SitesContext()
    private let service: CaddyService
    private let selection: SitesMachineSelection
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?
    private nonisolated(unsafe) var siteTasks: [String: Task<Void, Never>] = [:]
    private nonisolated(unsafe) var addTask: Task<Void, Never>?
    private nonisolated(unsafe) var removeTask: Task<Void, Never>?
    private nonisolated(unsafe) var dnsProvidersTask: Task<Void, Never>?
    private nonisolated(unsafe) var dnsRecordTasks: [String: Task<Void, Never>] = [:]

    init(service: CaddyService = CaddyService(), selection: SitesMachineSelection = SitesMachineSelection()) {
        self.service = service
        self.selection = selection
    }

    deinit {
        refreshTask?.cancel()
        for task in siteTasks.values { task.cancel() }
        addTask?.cancel()
        removeTask?.cancel()
        dnsProvidersTask?.cancel()
        for task in dnsRecordTasks.values { task.cancel() }
    }

    // MARK: - The selected machine

    var selectedState: MachineSitesState? {
        selectedMachine.flatMap { sitesByMachine[$0] }
    }

    var rows: [SubdomainRow] { selectedState?.rows ?? [] }
    var errorText: String? { machinesError ?? selectedState?.errorText }
    var notSetUpMessage: String? { selectedState?.notSetUpMessage }
    var isLoading: Bool { isLoadingMachines || (selectedState?.isLoading ?? false) }
    var showsMachinePicker: Bool { machines.count > 1 }
    var hasLoadedSites: Bool { selectedState?.hasLoaded ?? false }

    /// True until the selected machine's list has answered once. A later
    /// refresh keeps the rows on screen, so the skeleton never comes back.
    var showsSitesSkeleton: Bool { !hasLoadedSites && errorText == nil }

    /// A provider tab waits for the configured domain; when that read failed
    /// or found no domain, the tab says so instead of waiting.
    func dnsPhase(for provider: String) -> DNSRecordsPhase {
        if let error = dnsErrorByProvider[provider] { return .failed(error) }
        if let records = dnsRecordsByProvider[provider] { return .loaded(records) }
        if domain.isEmpty, let errorText { return .failed(errorText) }
        if domain.isEmpty, hasLoadedSites { return .failed(Self.noDomainMessage) }
        return .skeleton
    }

    /// DNS providers run on a server; this Mac has none to ask.
    var dnsMachine: String? {
        machines.first { $0.name == selectedMachine && !$0.isSelf }?.name
    }

    /// Nil when the CLI could not say where workspaces live: the add sheet
    /// then offers every remote workspace, as it did before machines.
    var workspacesOnSelectedMachine: [String]? {
        guard let selectedMachine, !context.workspaces.isEmpty else { return nil }
        return context.workspaces(on: selectedMachine)
    }

    func select(_ name: String) {
        guard machines.contains(where: { $0.name == name }), name != selectedMachine else { return }
        selectedMachine = name
        selection.machineName = name
        resetDNS()
        loadDNSProviders()
        if sitesByMachine[name] == nil, let machine = machines.first(where: { $0.name == name }) {
            loadSites(machine)
        }
    }

    /// Sets every machine's state at once — demo mode and render tests, which
    /// have nothing real to ask.
    func show(machines: [CLIMachine], states: [String: MachineSitesState], selected: String?) {
        self.machines = machines
        sitesByMachine = states
        selectedMachine = selected
        machinesError = nil
        isLoadingMachines = false
    }

    // MARK: - Loading

    func refresh() {
        if DemoMode.holdsLoading {
            dnsProviders = DemoData.dnsProviders
            isLoadingMachines = true
            return
        }
        if DemoMode.isActive {
            show(machines: DemoData.subdomainMachines, states: DemoData.subdomainStates,
                 selected: DemoData.subdomainSelectedMachine)
            domain = DemoData.domain
            dnsProviders = DemoData.dnsProviders
            return
        }
        refreshTask?.cancel()
        isLoadingMachines = true
        machinesError = nil
        let service = self.service

        refreshTask = Task {
            do {
                let (machines, context) = try await Task.detached {
                    (try service.machines(), service.context())
                }.value
                guard !Task.isCancelled else { return }
                self.apply(machines: machines, context: context)
            } catch {
                guard !Task.isCancelled else { return }
                self.machinesError = PackageGateMessage.friendly(for: error)
            }
            if !Task.isCancelled { self.isLoadingMachines = false }
        }
    }

    /// Reloads one machine only — the retry on its own error.
    func reload(machine name: String) {
        guard let machine = machines.first(where: { $0.name == name }) else { return refresh() }
        loadSites(machine)
    }

    private func apply(machines: [CLIMachine], context: SitesContext) {
        self.machines = machines
        self.context = context
        domain = context.domain
        sitesByMachine = sitesByMachine.filter { name, _ in machines.contains { $0.name == name } }

        let previous = selectedMachine
        let remembered = selection.machineName
        selectedMachine = machines.first { $0.name == remembered }?.name
            ?? machines.first { !$0.isSelf }?.name
            ?? machines.first?.name
        if previous != selectedMachine { resetDNS() }

        for machine in machines { loadSites(machine) }
        loadDNSProviders()
    }

    private func loadSites(_ machine: CLIMachine) {
        let name = machine.name
        siteTasks[name]?.cancel()
        update(name) { $0.isLoading = true }
        let service = self.service
        let context = self.context

        siteTasks[name] = Task {
            let result = await Task.detached { Result { try service.sites(on: machine, context: context) } }.value
            guard !Task.isCancelled else { return }
            self.update(name) { state in
                state.isLoading = false
                state.hasLoaded = true
                switch result {
                case .success(.sites(let rows)):
                    state.rows = rows
                    state.errorText = nil
                    state.notSetUpMessage = nil
                case .success(.notSetUp(let message)):
                    state.rows = []
                    state.errorText = nil
                    state.notSetUpMessage = message
                case .failure(let error):
                    state.errorText = PackageGateMessage.friendly(for: error)
                }
            }
            self.siteTasks[name] = nil
        }
    }

    private func update(_ machine: String, _ mutate: (inout MachineSitesState) -> Void) {
        var state = sitesByMachine[machine] ?? MachineSitesState()
        mutate(&state)
        sitesByMachine[machine] = state
    }

    // MARK: - DNS

    private func resetDNS() {
        dnsProvidersTask?.cancel()
        for task in dnsRecordTasks.values { task.cancel() }
        dnsRecordTasks = [:]
        dnsProviders = []
        dnsProvidersError = nil
        isLoadingDNSProviders = false
        dnsRecordsByProvider = [:]
        dnsErrorByProvider = [:]
        dnsLoadingProviders = []
    }

    func loadDNSProviders() {
        if DemoMode.isActive {
            dnsProviders = dnsMachine == nil ? [] : DemoData.dnsProviders
            isLoadingDNSProviders = false
            return
        }
        dnsProvidersTask?.cancel()
        guard let machine = dnsMachine else {
            dnsProviders = []
            isLoadingDNSProviders = false
            return
        }
        isLoadingDNSProviders = true
        dnsProvidersError = nil
        let service = self.service

        dnsProvidersTask = Task {
            do {
                let names = try await Task.detached { try service.dnsProviderNames(machine: machine) }.value
                guard !Task.isCancelled, self.dnsMachine == machine else { return }
                self.dnsProviders = names
                self.dnsProvidersError = nil
            } catch {
                guard !Task.isCancelled, self.dnsMachine == machine else { return }
                self.dnsProvidersError = PackageGateMessage.friendly(for: error)
            }
            if !Task.isCancelled { self.isLoadingDNSProviders = false }
        }
    }

    /// Loads `provider`'s records for the configured domain, once — a second
    /// call while the first is still running, or already loaded, is a no-op
    /// unless `force`.
    func loadRecords(provider: String, force: Bool = false) {
        if DemoMode.holdsLoading { return }
        if DemoMode.isActive {
            dnsRecordsByProvider[provider] = DemoData.dnsRecordsByProvider[provider] ?? []
            dnsLoadingProviders.remove(provider)
            return
        }
        guard force || (dnsRecordsByProvider[provider] == nil && dnsRecordTasks[provider] == nil) else { return }
        guard !domain.isEmpty, let machine = dnsMachine else { return }
        dnsRecordTasks[provider]?.cancel()
        dnsLoadingProviders.insert(provider)
        dnsErrorByProvider[provider] = nil
        let service = self.service
        let domain = self.domain

        dnsRecordTasks[provider] = Task {
            do {
                let records = try await Task.detached {
                    try service.dnsRecords(machine: machine, provider: provider, zone: domain)
                }.value
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

    // MARK: - Actions

    /// `expose add` finds the machine from the workspace, so only the list
    /// that changed is read again.
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
                self.reloadMachine(ofWorkspace: workspace)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.task?.id == taskID { self.task = nil }
            case .failure(let error):
                self.addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.task = nil
            }
        }
    }

    private func reloadMachine(ofWorkspace workspace: String) {
        if let name = context.workspaces.first(where: { $0.name == workspace })?.machine {
            reload(machine: name)
        } else {
            refresh()
        }
    }

    func remove(host: String) {
        guard let machine = selectedMachine else { return }
        removeTask?.cancel()
        removeError = nil
        removingHost = host
        let service = self.service

        removeTask = Task {
            do {
                try await Task.detached { try service.remove(host: host, machine: machine) }.value
                guard !Task.isCancelled else { return }
                self.reload(machine: machine)
            } catch {
                guard !Task.isCancelled else { return }
                self.removeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            if !Task.isCancelled { self.removingHost = nil }
        }
    }

    /// The Caddy log tail for one host on the selected machine — read on
    /// demand for the row's "Logs" action, not kept once the popover closes.
    func fetchLogs(host: String) async -> Result<String, Error> {
        guard let machine = selectedMachine else {
            return .failure(DevmachineCLIError.commandFailed("No machine is selected."))
        }
        let service = self.service
        return await Task.detached { Result { try service.logs(machine: machine, matching: host) } }.value
    }
}
