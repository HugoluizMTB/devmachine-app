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
    /// When the rows on screen were read, from the cache or a fresh fetch.
    var refreshedAt: Date?
    /// A refresh that failed while cached rows stay on screen.
    var refreshError: String?
}

/// One publish or removal the person started, shown as a card until it is
/// dismissed. The request is kept so Retry runs the same command again.
struct PublishJob: Identifiable, Equatable {
    enum Request: Equatable {
        case publish(workspace: String, port: Int, host: String, via: String? = nil)
        case remove(host: String, machine: String)

        var host: String {
            switch self {
            case .publish(_, _, let host, _), .remove(let host, _): return host
            }
        }

        var action: PublishProgress.Action {
            switch self {
            case .publish: return .publish
            case .remove: return .remove
            }
        }
    }

    let id: UUID
    let request: Request
    var progress: PublishProgress
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
    @Published private(set) var jobs: [PublishJob] = []
    /// Where a site can be served from and where each workspace lives, for
    /// the add sheet's "Published by". Empty until the CLI has answered.
    @Published private(set) var publishPlaces = PublishPlaces()
    /// True while the add sheet waits for its first answer about where
    /// things live; Create waits too, or a workspace on a machine without
    /// Caddy would be sent without `--via`.
    @Published private(set) var isLoadingPublishPlaces = false
    @Published var removingHost: String?

    /// The selected server's installed DNS providers — the tab strip's own
    /// list, separate from each tab's records.
    @Published var dnsProviders: [String] = []
    /// What `dns providers` said, zones and errors included; nil until it
    /// answered for the selected machine.
    @Published private(set) var dnsAnswers: [DNSProviderAnswer]?
    @Published var dnsProvidersError: String?
    @Published var isLoadingDNSProviders = false

    @Published var dnsRecordsByProvider: [String: [DNSRecordRow]] = [:]
    @Published var dnsErrorByProvider: [String: String] = [:]
    @Published var dnsLoadingProviders: Set<String> = []

    /// The stats `StatsStore` already polls, by machine: the rows' owners
    /// come from there instead of a second stats read per machine.
    var statsSnapshot: @MainActor (String) -> StatsSnapshot? = { _ in nil }
    /// How long a finished card stays before it leaves on its own. Saved
    /// and failed cards stay until dismissed: they ask for something.
    var liveCardLifetime: TimeInterval = 20
    var removedCardLifetime: TimeInterval = 6

    private var context = SitesContext()
    private let service: CaddyService
    private let selection: SitesMachineSelection
    let cache: DataCache
    let dnsSetup: DNSSetupStore

    init(
        service: CaddyService = CaddyService(), selection: SitesMachineSelection = SitesMachineSelection(),
        cache: DataCache = DataCache(), dnsSetup: DNSSetupStore? = nil
    ) {
        self.service = service
        self.selection = selection
        self.cache = cache
        self.dnsSetup = dnsSetup ?? DNSSetupStore(
            service: service,
            runner: DemoMode.isActive ? DemoDNSSyncRunner() as any PrepareRunning : ProcessPrepareRunner())
        if DemoMode.isActive {
            self.dnsSetup.canRunSync = { true }
            self.dnsSetup.canEditMachineSettings = { true }
        }
        self.dnsSetup.onConfigurationChanged = { [weak self] in self?.refresh(force: true) }
        self.dnsSetup.onSyncEnded = { [weak self] machine in
            guard let self, self.dnsMachine == machine else { return }
            self.loadDNSProviders(force: true)
        }
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
    ///
    /// A machine with caddy also offers the workspaces of machines without
    /// it: it can serve them with `--via`.
    var workspacesOnSelectedMachine: [String]? {
        guard let selectedMachine, !context.workspaces.isEmpty else { return nil }
        let own = context.workspaces(on: selectedMachine)
        let serving = publishPlaces.servingMachines
        guard serving.contains(selectedMachine) else { return own }
        let unserved = context.workspaces.filter { !serving.contains($0.machine) }.map(\.name)
        return own + unserved.filter { !own.contains($0) }
    }

    /// The add sheet opened before the Subdomains page ever loaded. Only the
    /// configuration is read (cache first), never a machine's site list: a
    /// sheet opening must not cost an ssh per machine.
    func loadPublishPlacesIfNeeded() {
        guard machines.isEmpty, !DemoMode.isActive else { return }
        let key = MachineDataKeys.sitesContext
        let cached = cache.revalidate(key, force: false, fetch: sitesContextFetch(), onUpdate: { [weak self] update in
            guard let self else { return }
            self.isLoadingPublishPlaces = false
            self.cache.put(MachineDataKeys.workspaces, update.cached.value.workspaces)
            self.updatePublishPlaces(update.cached.value.machines, update.cached.value.context)
        }, onError: { [weak self] _ in
            self?.isLoadingPublishPlaces = false
        })
        if let cached {
            updatePublishPlaces(cached.value.machines, cached.value.context)
        }
        isLoadingPublishPlaces = cached == nil && cache.isRefreshing(key)
    }

    private func sitesContextFetch() -> @Sendable () throws -> SitesContextSnapshot {
        let service = self.service
        return {
            let machines = try service.machines()
            let context = service.context()
            return SitesContextSnapshot(
                machines: machines, domain: context.domain, workspaces: context.workspaces,
                installedPackages: context.installedPackages)
        }
    }

    private func updatePublishPlaces(_ machines: [CLIMachine], _ context: SitesContext) {
        let places = PublishPlaces(
            servingMachines: machines
                .filter { !$0.isSelf && context.hasCaddy(onMachine: $0.name) == true }
                .map(\.name),
            machineOf: Dictionary(context.workspaces.map { ($0.name, $0.machine) }, uniquingKeysWith: { first, _ in first }))
        if places != publishPlaces { publishPlaces = places }
    }

    func select(_ name: String) {
        guard machines.contains(where: { $0.name == name }), name != selectedMachine else { return }
        selectedMachine = name
        selection.machineName = name
        resetDNS()
        loadDNSProviders()
        if let machine = machines.first(where: { $0.name == name }) {
            loadSites(machine)
        }
    }

    /// Selects a machine now when its list is in, or remembers it so the
    /// first load opens on it.
    func prefer(machine name: String) {
        if machines.contains(where: { $0.name == name }) {
            select(name)
        } else {
            selection.machineName = name
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

    /// Opening the page: what is cached draws at once, and only what is
    /// older than its TTL is read again in the background.
    func appear() {
        refresh(force: false)
    }

    /// The Refresh button reads everything again, whatever its age.
    func refresh() {
        refresh(force: true)
    }

    func refresh(force: Bool) {
        if DemoMode.holdsLoading {
            dnsProviders = DemoData.dnsProviders
            isLoadingMachines = true
            return
        }
        if DemoMode.isActive {
            show(machines: DemoData.subdomainMachines, states: DemoData.subdomainStates,
                 selected: DemoData.subdomainSelectedMachine)
            publishPlaces = DemoData.publishPlaces
            domain = DemoData.domain
            loadDNSProviders()
            return
        }
        let key = MachineDataKeys.sitesContext
        machinesError = nil
        let cached = cache.revalidate(key, force: force, fetch: sitesContextFetch(), onUpdate: { [weak self] update in
            guard let self else { return }
            self.isLoadingMachines = false
            self.cache.put(MachineDataKeys.workspaces, update.cached.value.workspaces)
            if update.changed || self.machines.isEmpty {
                self.apply(update.cached.value, force: force)
            }
        }, onError: { [weak self] error in
            guard let self else { return }
            self.isLoadingMachines = false
            if self.machines.isEmpty {
                self.machinesError = PackageGateMessage.friendly(for: error)
            }
        })
        if let cached {
            apply(cached.value, force: force)
        }
        isLoadingMachines = cache.isRefreshing(key)
    }

    /// Reloads one machine only — the retry on its own error.
    func reload(machine name: String) {
        guard let machine = machines.first(where: { $0.name == name }) else { return refresh() }
        loadSites(machine, force: true)
    }

    private func apply(_ snapshot: SitesContextSnapshot, force: Bool) {
        if machines != snapshot.machines { machines = snapshot.machines }
        context = snapshot.context
        updatePublishPlaces(machines, context)
        if domain != snapshot.domain { domain = snapshot.domain }
        sitesByMachine = sitesByMachine.filter { name, _ in snapshot.machines.contains { $0.name == name } }

        let previous = selectedMachine
        let remembered = selection.machineName
        let chosen = machines.first { $0.name == remembered }?.name
            ?? (previous.flatMap { name in machines.first { $0.name == name }?.name })
            ?? machines.first { !$0.isSelf }?.name
            ?? machines.first?.name
        if chosen != selectedMachine { selectedMachine = chosen }
        if previous != selectedMachine { resetDNS() }
        updateDNSSetup()
        loadAll(force: force)
    }

    private func loadAll(force: Bool) {
        for machine in machines { loadSites(machine, force: force) }
        loadDNSProviders(force: force)
    }

    private func loadSites(_ machine: CLIMachine, force: Bool = false) {
        let name = machine.name
        if let answer = service.preflight(machine, context: context) {
            update(name) { state in
                state.isLoading = false
                state.hasLoaded = true
                if case .notSetUp(let message) = answer {
                    state.rows = []
                    state.errorText = nil
                    state.notSetUpMessage = message
                }
            }
            return
        }
        let key = MachineDataKeys.sites(name)
        let service = self.service
        let cached = cache.revalidate(key, force: force, fetch: {
            try service.listing(on: name)
        }, onUpdate: { [weak self] update in
            guard let self else { return }
            self.show(update.cached, on: machine)
            self.update(name) { $0.isLoading = false }
        }, onError: { [weak self] error in
            guard let self else { return }
            let message = PackageGateMessage.friendly(for: error)
            self.update(name) { state in
                state.isLoading = false
                state.hasLoaded = true
                if state.refreshedAt == nil {
                    state.errorText = message
                } else {
                    state.refreshError = message
                }
            }
        })
        if let cached { show(cached, on: machine) }
        let refreshing = cache.isRefreshing(key)
        if sitesByMachine[name]?.isLoading != refreshing {
            update(name) { $0.isLoading = refreshing }
        }
    }

    /// Lays a listing over the rows on screen by host, so a refresh that
    /// changed one site moves only that row.
    private func show(_ cached: Cached<ExposureListing>, on machine: CLIMachine) {
        let result = CaddyService.result(
            for: machine, listing: cached.value, context: context, snapshot: statsSnapshot(machine.name))
        update(machine.name) { state in
            state.hasLoaded = true
            state.refreshedAt = cached.fetchedAt
            state.refreshError = nil
            state.errorText = nil
            switch result {
            case .sites(let rows):
                let merge = StableList.merge(old: state.rows, new: rows)
                if merge.changed || state.rows.isEmpty != rows.isEmpty { state.rows = merge.list }
                state.notSetUpMessage = nil
            case .notSetUp(let message):
                state.rows = []
                state.notSetUpMessage = message
            }
        }
    }

    private func update(_ machine: String, _ mutate: (inout MachineSitesState) -> Void) {
        var state = sitesByMachine[machine] ?? MachineSitesState()
        mutate(&state)
        if sitesByMachine[machine] != state { sitesByMachine[machine] = state }
    }

    // MARK: - DNS

    private func resetDNS() {
        dnsProviders = []
        dnsAnswers = nil
        dnsProvidersError = nil
        isLoadingDNSProviders = false
        dnsRecordsByProvider = [:]
        dnsErrorByProvider = [:]
        dnsLoadingProviders = []
        updateDNSSetup()
    }

    func loadDNSProviders(force: Bool = false) {
        if DemoMode.isActive {
            showDNSAnswers(dnsMachine == nil ? nil : DemoData.dnsAnswers)
            isLoadingDNSProviders = false
            return
        }
        guard let machine = dnsMachine else {
            showDNSAnswers(nil)
            isLoadingDNSProviders = false
            return
        }
        let key = MachineDataKeys.dnsProviders(machine)
        let service = self.service
        let cached = cache.revalidate(key, force: force, fetch: {
            try service.dnsProviders(machine: machine)
        }, onUpdate: { [weak self] update in
            guard let self, self.dnsMachine == machine else { return }
            self.showDNSAnswers(update.cached.value)
            self.dnsProvidersError = nil
            self.isLoadingDNSProviders = false
            if force { self.reloadLoadedRecords() }
        }, onError: { [weak self] error in
            guard let self, self.dnsMachine == machine else { return }
            self.dnsProvidersError = PackageGateMessage.friendly(for: error)
            self.isLoadingDNSProviders = false
        })
        if let cached {
            showDNSAnswers(cached.value)
            dnsProvidersError = nil
        }
        isLoadingDNSProviders = cache.isRefreshing(key)
    }

    private func showDNSAnswers(_ answers: [DNSProviderAnswer]?) {
        if dnsAnswers != answers { dnsAnswers = answers }
        let names = answers?.map(\.name) ?? []
        if dnsProviders != names { dnsProviders = names }
        updateDNSSetup()
    }

    /// Only a server that publishes sites gets the DNS setup card: on this
    /// Mac, or a server without caddy, there is nothing to make records for.
    private func updateDNSSetup() {
        let machine = dnsMachine.flatMap { name in context.hasCaddy(onMachine: name) == false ? nil : name }
        let packages = DemoMode.isActive ? DemoData.dnsPackages : context.installedPackages
        dnsSetup.update(machine: machine, packages: packages, answers: machine == nil ? nil : dnsAnswers)
    }

    private func reloadLoadedRecords() {
        for provider in dnsRecordsByProvider.keys { loadRecords(provider: provider, force: true) }
    }

    /// `provider`'s records for the configured domain: the cached ones draw
    /// at once, and a stale or `force`d read runs in the background.
    func loadRecords(provider: String, force: Bool = false) {
        if DemoMode.holdsLoading { return }
        if DemoMode.isActive {
            dnsRecordsByProvider[provider] = DemoData.dnsRecordsByProvider[provider] ?? []
            dnsLoadingProviders.remove(provider)
            return
        }
        guard !domain.isEmpty, let machine = dnsMachine else { return }
        let domain = self.domain
        let key = MachineDataKeys.dnsRecords(machine: machine, provider: provider, zone: domain)
        let service = self.service
        let cached = cache.revalidate(key, force: force, fetch: {
            try service.dnsRecords(machine: machine, provider: provider, zone: domain)
        }, onUpdate: { [weak self] update in
            guard let self, self.dnsMachine == machine else { return }
            self.showRecords(update.cached.value, provider: provider)
            self.dnsLoadingProviders.remove(provider)
        }, onError: { [weak self] error in
            guard let self, self.dnsMachine == machine else { return }
            if self.dnsRecordsByProvider[provider] == nil {
                self.dnsErrorByProvider[provider] = PackageGateMessage.friendly(for: error)
            }
            self.dnsLoadingProviders.remove(provider)
        })
        if let cached {
            showRecords(cached.value, provider: provider)
        }
        if cache.isRefreshing(key) {
            dnsLoadingProviders.insert(provider)
        }
    }

    private func showRecords(_ records: [DNSRecordRow], provider: String) {
        let merge = StableList.merge(old: dnsRecordsByProvider[provider] ?? [], new: records)
        if dnsRecordsByProvider[provider] == nil || merge.changed {
            dnsRecordsByProvider[provider] = merge.list
        }
        dnsErrorByProvider[provider] = nil
    }

    // MARK: - Publishing

    /// `expose add` finds the machine from the workspace. The card in the
    /// corner follows it from "Publishing…" to the live address.
    func addSubdomain(_ req: SubdomainRequest, workspace: String, via: String? = nil) {
        start(.publish(workspace: workspace, port: req.port, host: req.host, via: via))
    }

    func remove(host: String) {
        guard let machine = selectedMachine else { return }
        start(.remove(host: host, machine: machine))
    }

    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].progress = .running(jobs[index].request.action, host: jobs[index].request.host)
        run(id)
    }

    func dismiss(_ id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    /// Demo mode and render tests: a card in any state without a CLI.
    func showJob(_ job: PublishJob) {
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
    }

    private func start(_ request: PublishJob.Request) {
        let job = PublishJob(id: UUID(), request: request, progress: .running(request.action, host: request.host))
        jobs.append(job)
        run(job.id)
    }

    private func run(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let request = job.request
        if case .remove(let host, _) = request { removingHost = host }
        guard !DemoMode.isActive else {
            finish(id, .couldNotStart(request.action, host: request.host,
                                      message: "Demo mode never publishes a real subdomain."))
            return
        }
        let service = self.service
        Task {
            let progress = await Task.detached { () -> PublishProgress in
                do {
                    switch request {
                    case let .publish(workspace, port, host, via):
                        let output = try service.publish(workspace: workspace, port: port, host: host, via: via)
                        return .finished(.publish, host: host, output: output)
                    case let .remove(host, machine):
                        let output = try service.remove(host: host, machine: machine)
                        return .finished(.remove, host: host, output: output)
                    }
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    return .couldNotStart(request.action, host: request.host, message: message)
                }
            }.value
            self.finish(id, progress)
        }
    }

    private func finish(_ id: UUID, _ progress: PublishProgress) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].progress = progress
        let request = jobs[index].request
        if removingHost == request.host { removingHost = nil }
        if progress.changedTheMachine { invalidate(after: request) }
        let lifetime: TimeInterval?
        let asksForSomething = progress.steps.contains { $0.state == .attention }
        switch progress.outcome {
        case .live where asksForSomething: lifetime = nil
        case .live: lifetime = liveCardLifetime
        case .removed: lifetime = removedCardLifetime
        default: lifetime = nil
        }
        if let lifetime {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
                if self.jobs.first(where: { $0.id == id })?.progress == progress { self.dismiss(id) }
            }
        }
    }

    /// A publish changes the machine's sites and may write a DNS record: both
    /// are read again now, and every view on the same keys hears it.
    private func invalidate(after request: PublishJob.Request) {
        let machine: String?
        switch request {
        case .publish(_, _, _, let via?):
            machine = via
        case .publish(let workspace, _, _, nil):
            machine = context.workspaces.first { $0.name == workspace }?.machine
                ?? cache.cached(MachineDataKeys.workspaces)?.value.first { $0.name == workspace }?.machine
        case .remove(_, let name):
            machine = name
        }
        guard let machine else {
            cache.invalidate(.sites)
            cache.invalidate(.dnsRecords)
            refresh(force: true)
            return
        }
        cache.invalidate(.sites, scope: machine)
        cache.invalidate(.dnsRecords, scopePrefix: MachineDataKeys.dnsRecordsPrefix(machine: machine))
        if let entry = machines.first(where: { $0.name == machine }) {
            loadSites(entry, force: true)
        } else {
            refresh(force: true)
        }
        if dnsMachine == machine { reloadLoadedRecords() }
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
