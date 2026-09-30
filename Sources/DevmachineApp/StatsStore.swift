import Foundation
import AppKit
import DevmachineCore

/// One non-self machine Stats can switch to: its name and, for the switcher's
/// small subtitle, its first configured address.
struct StatsMachine: Identifiable, Equatable, Sendable {
    let name: String
    let firstAddress: String?
    var id: String { name }
}

/// A single machine's own snapshot, loading flag, error and last-updated
/// time — Stats keeps one of these per machine so switching tabs never mixes
/// one host's numbers with another's.
struct MachineStatsState: Equatable, Sendable {
    var snapshot: StatsSnapshot?
    var isLoading = false
    var errorText: String?
    var refreshedAt: Date?

    /// A machine with nothing to show yet: no snapshot and no error.
    var showsSkeleton: Bool { snapshot == nil && errorText == nil && isLoading }

    func isStale(now: Date) -> Bool {
        guard let refreshedAt else { return false }
        return StatsFreshness.isStale(since: refreshedAt, now: now)
    }
}

private enum MachineFetchResult: Sendable {
    case success(StatsSnapshot)
    case failure(String)
}

/// Remembers which machine Stats last showed, across launches. A per-viewer
/// convenience (UserDefaults), never a source of truth about which machines
/// exist.
final class StatsMachineSelection: @unchecked Sendable {
    private static let key = "StatsStore.selectedMachine"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var machineName: String? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// The one app-wide source of machine stats. Home's machine cards and the
/// Stats page both read it; a timer polls every configured machine on its
/// own schedule (`StatsPollSchedule`), and the last good snapshot per
/// machine is kept on disk (`StatsCache`) so both draw at launch before any
/// machine answers.
@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var machines: [StatsMachine] = []
    @Published private(set) var selectedMachine: String?
    @Published private(set) var states: [String: MachineStatsState] = [:]
    /// True once there is a machine list to show, from the cache or the CLI.
    @Published private(set) var hasLoadedMachines = false
    /// True once the CLI answered (or failed to answer) the machine list.
    @Published private(set) var hasLoadedMachineList = false

    private let cli: @Sendable () throws -> DevmachineCLI
    private let selection: StatsMachineSelection
    private let cache: StatsCache?
    private let tickInterval: TimeInterval?
    private let now: @MainActor () -> Date
    private var schedule: StatsPollSchedule
    private var started = false
    private var isAsleep = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var loadMachinesTask: Task<Void, Never>?

    init(
        cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() },
        selection: StatsMachineSelection = StatsMachineSelection(),
        cache: StatsCache? = StatsCache(fileURL: StatsCache.defaultFileURL),
        policy: StatsPollPolicy = .standard,
        tickInterval: TimeInterval? = 1,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.cli = cli
        self.selection = selection
        self.cache = cache
        self.tickInterval = tickInterval
        self.now = now
        self.schedule = StatsPollSchedule(policy: policy)
    }

    var pollInterval: TimeInterval { schedule.policy.interval }

    /// The Stats page shows its tabs only past one machine.
    var showsSwitcher: Bool { machines.count > 1 }

    var snapshot: StatsSnapshot? { state(for: selectedMachine)?.snapshot }
    var isLoading: Bool { state(for: selectedMachine)?.isLoading ?? false }
    var errorText: String? { state(for: selectedMachine)?.errorText }
    var refreshedAt: Date? { state(for: selectedMachine)?.refreshedAt }

    /// True only while the selected machine has nothing at all to show: no
    /// cached or fresh snapshot and no error. A refresh keeps what is there.
    var showsSkeleton: Bool {
        guard let machine = selectedMachine else { return !hasLoadedMachines }
        guard let state = states[machine] else { return true }
        return state.snapshot == nil && state.errorText == nil
    }

    func state(for machine: String?) -> MachineStatsState? {
        guard let machine else { return nil }
        return states[machine]
    }

    /// Idempotent: draws the cache, asks the CLI for the machine list, and
    /// starts the poller. Called when the main window first shows.
    func start() {
        guard !started else { return }
        started = true
        if DemoMode.isActive {
            seedDemo()
            return
        }
        restoreFromCache()
        loadMachines()
        startTimer()
    }

    /// Re-reads the configured machines. A failed read keeps the cached ones.
    func loadMachines() {
        loadMachinesTask?.cancel()
        let cli = self.cli
        loadMachinesTask = Task {
            let list = await Task.detached { () -> [StatsMachine]? in
                try? cli().nonSelfMachines().map {
                    StatsMachine(name: $0.name, firstAddress: $0.hosts.first)
                }
            }.value
            guard !Task.isCancelled else { return }
            self.hasLoadedMachineList = true
            self.hasLoadedMachines = true
            if let list { self.apply(machineList: list) }
            self.tick()
        }
    }

    /// Runs every machine that is due and has nothing in flight.
    func tick() {
        guard !isAsleep, !DemoMode.isActive else { return }
        for name in schedule.due(now: now()) { fetch(name) }
    }

    /// The refresh button: every machine now, the selected one first, and
    /// the backoff starts over.
    func refresh() {
        guard !DemoMode.isActive else { return }
        schedule.refreshAll(now: now(), first: selectedMachine)
        tick()
        loadMachines()
    }

    /// Switches the Stats tab and remembers it; the cache draws it at once.
    func select(_ name: String) {
        guard machines.contains(where: { $0.name == name }) else { return }
        selectedMachine = name
        selection.machineName = name
        refreshIfStale(name)
    }

    /// Opening a machine whose snapshot is older than one interval reads it
    /// again in the background. A machine in backoff after an error waits
    /// for its turn or the refresh button.
    func refreshIfStale(_ name: String) {
        guard !DemoMode.isActive, let state = states[name], state.errorText == nil else { return }
        if let refreshedAt = state.refreshedAt,
           now().timeIntervalSince(refreshedAt) < schedule.policy.interval { return }
        schedule.makeDue(name, now: now())
        tick()
    }

    func handleSleep() {
        isAsleep = true
    }

    /// Every ssh started just before sleep failed, so the backoff it built
    /// says nothing about the machines now.
    func handleWake() {
        isAsleep = false
        schedule.refreshAll(now: now(), first: selectedMachine)
        tick()
    }

    private func startTimer() {
        guard let tickInterval else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSleep() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        })
    }

    private func restoreFromCache() {
        guard let cache else { return }
        let entries = cache.load()
        guard !entries.isEmpty else { return }
        machines = entries.map { StatsMachine(name: $0.machine, firstAddress: $0.firstAddress) }
        states = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.machine, MachineStatsState(snapshot: $0.snapshot, refreshedAt: $0.collectedAt))
        })
        hasLoadedMachines = true
        selectRememberedMachine()
    }

    private func apply(machineList list: [StatsMachine]) {
        let names = Set(list.map(\.name))
        let removed = states.keys.filter { !names.contains($0) }
        machines = list
        for name in removed { states[name] = nil }
        let lastSuccess = states.compactMapValues { $0.snapshot == nil ? nil : $0.refreshedAt }
        schedule.setMachines(list.map(\.name), lastSuccess: lastSuccess, now: now())
        if !removed.isEmpty { persist() }
        selectRememberedMachine()
    }

    private func selectRememberedMachine() {
        guard !machines.isEmpty else {
            selectedMachine = nil
            return
        }
        if let current = selectedMachine, machines.contains(where: { $0.name == current }) { return }
        let remembered = selection.machineName
        selectedMachine = machines.first { $0.name == remembered }?.name ?? machines[0].name
    }

    private func fetch(_ machine: String) {
        guard schedule.begin(machine) else { return }
        update(machine) { $0.isLoading = true }
        let cli = self.cli
        Task {
            let result = await Self.fetchSnapshot(machine: machine, cli: cli)
            self.apply(result, to: machine)
        }
    }

    private func apply(_ result: MachineFetchResult, to machine: String) {
        let finishedAt = now()
        switch result {
        case .success:
            schedule.succeed(machine, now: finishedAt)
        case .failure:
            schedule.fail(machine, now: finishedAt)
        }
        guard machines.contains(where: { $0.name == machine }) else { return }
        switch result {
        case .success(let snapshot):
            update(machine) {
                $0.snapshot = snapshot
                $0.errorText = nil
                $0.refreshedAt = finishedAt
                $0.isLoading = false
            }
            persist()
        case .failure(let message):
            // The last good snapshot stays on screen, under the error
            // banner: a blip does not have to blank the panel a beta tester
            // was just reading.
            update(machine) {
                $0.errorText = message
                $0.isLoading = false
            }
        }
    }

    private func persist() {
        guard let cache else { return }
        let entries = machines.compactMap { machine -> CachedMachineStats? in
            guard let state = states[machine.name], let snapshot = state.snapshot,
                  let refreshedAt = state.refreshedAt else { return nil }
            return CachedMachineStats(
                machine: machine.name, firstAddress: machine.firstAddress,
                collectedAt: refreshedAt, snapshot: snapshot)
        }
        try? cache.save(entries)
    }

    private func update(_ machine: String, _ mutate: (inout MachineStatsState) -> Void) {
        var state = states[machine] ?? MachineStatsState()
        mutate(&state)
        states[machine] = state
    }

    private func seedDemo() {
        machines = DemoData.statsMachines
        selectedMachine = "main"
        hasLoadedMachines = true
        hasLoadedMachineList = true
        let date = now()
        states = Dictionary(uniqueKeysWithValues: DemoData.statsSnapshots.map { name, snapshot in
            let state = DemoMode.holdsLoading
                ? MachineStatsState(isLoading: true)
                : MachineStatsState(
                    snapshot: snapshot,
                    errorText: DemoData.statsErrors[name],
                    refreshedAt: date.addingTimeInterval(-(DemoData.statsAges[name] ?? 0)))
            return (name, state)
        })
    }

    private static func fetchSnapshot(
        machine: String, cli: @escaping @Sendable () throws -> DevmachineCLI
    ) async -> MachineFetchResult {
        do {
            let output = try await Task.detached {
                try cli().run(machine: machine, package: "devmachine-app", args: ["stats"])
            }.value
            guard let parsed = StatsParser.parse(output) else {
                return .failure("The host returned no usable stats.")
            }
            return .success(parsed)
        } catch {
            return .failure(PackageGateMessage.friendly(for: error))
        }
    }
}
