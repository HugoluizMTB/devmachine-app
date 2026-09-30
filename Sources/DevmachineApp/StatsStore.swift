import Foundation
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

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var machines: [StatsMachine] = []
    @Published private(set) var selectedMachine: String?
    @Published private(set) var states: [String: MachineStatsState] = [:]
    @Published private(set) var hasLoadedMachines = false

    private let cli: @Sendable () throws -> DevmachineCLI
    private let selection: StatsMachineSelection
    /// How many machines the overview fetches at once — enough to feel
    /// parallel, not so many that ten machines open ten ssh connections at
    /// the same moment.
    private let overviewConcurrencyLimit: Int
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?
    private nonisolated(unsafe) var overviewTask: Task<Void, Never>?
    private nonisolated(unsafe) var loadMachinesTask: Task<Void, Never>?

    init(
        cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() },
        selection: StatsMachineSelection = StatsMachineSelection(),
        overviewConcurrencyLimit: Int = 3
    ) {
        self.cli = cli
        self.selection = selection
        self.overviewConcurrencyLimit = overviewConcurrencyLimit
    }

    deinit {
        refreshTask?.cancel()
        overviewTask?.cancel()
        loadMachinesTask?.cancel()
    }

    /// The Stats page shows a switcher only past one machine; a single
    /// machine (or the config lookup itself failing) reads as today's page.
    var showsSwitcher: Bool { machines.count > 1 }

    var snapshot: StatsSnapshot? { state(for: selectedMachine)?.snapshot }
    var isLoading: Bool { state(for: selectedMachine)?.isLoading ?? false }
    var errorText: String? { state(for: selectedMachine)?.errorText }
    var refreshedAt: Date? { state(for: selectedMachine)?.refreshedAt }

    /// True until the selected machine has a snapshot or an error to show. A
    /// refresh after that keeps the last snapshot, so it never comes back.
    var showsSkeleton: Bool {
        guard hasLoadedMachines else { return true }
        guard let machine = selectedMachine else { return false }
        guard let state = states[machine] else { return true }
        return state.snapshot == nil && state.errorText == nil
    }

    func state(for machine: String?) -> MachineStatsState? {
        guard let machine else { return nil }
        return states[machine]
    }

    /// Resolves the non-self machines, restores the remembered selection (or
    /// falls back to the first machine), then fetches the selected machine
    /// and, when there is more than one, every machine for the overview row.
    func loadMachines() {
        if DemoMode.isActive {
            machines = DemoData.statsMachines
            selectedMachine = "main"
            hasLoadedMachines = true
            states = DemoData.statsSnapshots.mapValues {
                DemoMode.holdsLoading
                    ? MachineStatsState(isLoading: true)
                    : MachineStatsState(snapshot: $0, isLoading: false, errorText: nil, refreshedAt: Date())
            }
            return
        }
        loadMachinesTask?.cancel()
        let cli = self.cli
        loadMachinesTask = Task {
            let list = await Task.detached { () -> [StatsMachine] in
                (try? cli().nonSelfMachines().map {
                    StatsMachine(name: $0.name, firstAddress: $0.hosts.first)
                }) ?? []
            }.value
            guard !Task.isCancelled else { return }
            self.machines = list
            self.hasLoadedMachines = true
            guard !list.isEmpty else {
                self.selectedMachine = nil
                return
            }
            let remembered = self.selection.machineName
            let name = list.first { $0.name == remembered }?.name ?? list[0].name
            self.selectedMachine = name
            self.refresh()
            if list.count > 1 { self.refreshOverview() }
        }
    }

    /// Switches the selected machine and remembers it; fetches it only if it
    /// has never been fetched, so tapping back and forth between tabs never
    /// re-runs a live host's stats needlessly.
    func select(_ name: String) {
        guard machines.contains(where: { $0.name == name }) else { return }
        selectedMachine = name
        selection.machineName = name
        if states[name]?.snapshot == nil { refresh() }
    }

    func refresh() {
        guard !DemoMode.isActive else { return }
        guard let machine = selectedMachine else { return }
        refreshTask?.cancel()
        setLoading(machine, true)
        let cli = self.cli
        refreshTask = Task {
            let (_, result) = await Self.fetchSnapshot(machine: machine, cli: cli)
            guard !Task.isCancelled else { return }
            self.apply(result, to: machine)
        }
    }

    /// Every machine, concurrently up to `overviewConcurrencyLimit` at a
    /// time — the overview row's compact cards need every machine's numbers,
    /// not just the selected one.
    func refreshOverview() {
        guard !DemoMode.isActive else { return }
        overviewTask?.cancel()
        let names = machines.map(\.name)
        guard !names.isEmpty else { return }
        for name in names { setLoading(name, true) }
        let cli = self.cli
        let limit = max(1, overviewConcurrencyLimit)
        overviewTask = Task {
            await withTaskGroup(of: (String, MachineFetchResult).self) { group in
                var iterator = names.makeIterator()
                func launchNext() {
                    guard let name = iterator.next() else { return }
                    group.addTask { await Self.fetchSnapshot(machine: name, cli: cli) }
                }
                for _ in 0..<limit { launchNext() }
                while let (name, result) = await group.next() {
                    if Task.isCancelled { break }
                    self.apply(result, to: name)
                    launchNext()
                }
            }
        }
    }

    private func setLoading(_ machine: String, _ loading: Bool) {
        update(machine) { $0.isLoading = loading }
    }

    private func apply(_ result: MachineFetchResult, to machine: String) {
        switch result {
        case .success(let snapshot):
            update(machine) {
                $0.snapshot = snapshot
                $0.errorText = nil
                $0.refreshedAt = Date()
                $0.isLoading = false
            }
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

    private func update(_ machine: String, _ mutate: (inout MachineStatsState) -> Void) {
        var state = states[machine] ?? MachineStatsState()
        mutate(&state)
        states[machine] = state
    }

    private static func fetchSnapshot(
        machine: String, cli: @escaping @Sendable () throws -> DevmachineCLI
    ) async -> (String, MachineFetchResult) {
        do {
            let output = try await Task.detached {
                try cli().run(machine: machine, package: "devmachine-app", args: ["stats"])
            }.value
            guard let parsed = StatsParser.parse(output) else {
                return (machine, .failure("The host returned no usable stats."))
            }
            return (machine, .success(parsed))
        } catch {
            return (machine, .failure(PackageGateMessage.friendly(for: error)))
        }
    }
}
