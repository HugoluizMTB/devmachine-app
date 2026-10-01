import Foundation
import DevmachineCore

/// Reads what this Mac listens on. A workspace's targets come from cached
/// machine data instead (`WorkspaceMachineData`).
struct PreviewTargetsService: Sendable {
    static let lsof = "/usr/sbin/lsof"

    let localRunner: any CommandRunner

    init(localRunner: any CommandRunner = ProcessRunner()) {
        self.localRunner = localRunner
    }

    func localTargets() throws -> [PreviewTarget] {
        let output = try localRunner.run(
            executable: Self.lsof, args: ListeningPortsParser.arguments + ["-a", "-u", NSUserName()],
            environment: nil)
        return PreviewTargets.local(ListeningPortsParser.parse(output))
    }
}

extension PreviewPlace {
    var key: String {
        switch self {
        case .thisMac: return "local"
        case let .workspace(name): return "ws:" + name
        }
    }
}

/// The Preview tab's list, per workspace. A workspace draws at once from the
/// cached sites and the stats poller's ports, then reads only what is old;
/// a publish or a removal elsewhere reaches it through the cache.
@MainActor
final class PreviewTargetsStore: ObservableObject {
    static let shared = PreviewTargetsStore(data: .shared)

    enum Phase: Equatable {
        case loading
        case loaded([PreviewTarget])
        case failed(String)
    }

    @Published private(set) var phases: [String: Phase] = [:]
    @Published private(set) var refreshedAt: [String: Date] = [:]
    @Published private(set) var refreshing: Set<String> = []

    private let service: PreviewTargetsService
    private let data: WorkspaceMachineData
    private weak var stats: PortStatsSource?

    init(service: PreviewTargetsService = PreviewTargetsService(), data: WorkspaceMachineData = WorkspaceMachineData()) {
        self.service = service
        self.data = data
        data.cache.observe { [weak self] entry in
            guard entry.kind == .sites || entry.kind == .workspaces else { return }
            self?.recomputeWorkspaces(onMachine: entry.kind == .sites ? entry.scope : nil)
        }
    }

    func phase(for place: PreviewPlace) -> Phase? { phases[place.key] }

    func isRefreshing(_ place: PreviewPlace) -> Bool { refreshing.contains(place.key) }

    /// Every workspace's last list, for ⌘K.
    func knownTargets() -> [(place: PreviewPlace, targets: [PreviewTarget])] {
        phases.compactMap { key, phase in
            guard case let .loaded(targets) = phase else { return nil }
            let place: PreviewPlace = key == "local" ? .thisMac : .workspace(String(key.dropFirst(3)))
            return (place, targets)
        }
        .sorted { $0.place.key < $1.place.key }
    }

    func show(_ targets: [PreviewTarget], for place: PreviewPlace) {
        phases[place.key] = .loaded(targets)
    }

    func load(_ place: PreviewPlace, stats: PortStatsSource, force: Bool = false) {
        let key = place.key
        if DemoMode.isActive {
            phases[key] = .loaded(DemoData.previewTargets(for: place))
            return
        }
        self.stats = stats
        switch place {
        case .thisMac:
            loadLocal(force: force)
        case let .workspace(name):
            loadWorkspace(name, stats: stats, force: force)
        }
    }

    private func loadLocal(force: Bool) {
        let key = PreviewPlace.thisMac.key
        guard !refreshing.contains(key) else { return }
        if !force, case .loaded = phases[key] { return }
        if case .loaded = phases[key] {} else { phases[key] = .loading }
        refreshing.insert(key)
        let service = self.service
        Task {
            let result = await Task.detached { Result { try service.localTargets() } }.value
            refreshing.remove(key)
            switch result {
            case let .success(targets): setLoaded(key, targets, at: Date())
            case let .failure(error): phases[key] = .failed(PackageGateMessage.friendly(for: error))
            }
        }
    }

    private func loadWorkspace(_ name: String, stats: PortStatsSource, force: Bool) {
        let key = PreviewPlace.workspace(name).key
        if let reading = cachedTargets(name, stats: stats) {
            setLoaded(key, reading.targets, at: reading.asOf)
        } else if phases[key] == nil {
            phases[key] = .loading
        }
        guard !refreshing.contains(key) else { return }
        if !force, let entry = data.cachedEntry(name), isFresh(entry, stats: stats) { return }
        refreshing.insert(key)
        let data = self.data
        Task {
            defer { self.refreshing.remove(key) }
            guard let entry = await data.entry(name) else {
                if case .loaded = self.phases[key] { return }
                self.phases[key] = .failed("The CLI has no workspace named \(name).")
                return
            }
            do {
                _ = try await data.sites(machine: entry.machine, force: force)
            } catch {
                if data.cachedSites(machine: entry.machine) == nil {
                    self.phases[key] = .failed(PackageGateMessage.friendly(for: error))
                    return
                }
            }
            _ = await stats.freshSnapshot(entry.machine, maxAge: force ? 0 : data.portsTTL)
            if let reading = self.cachedTargets(name, stats: stats) {
                self.setLoaded(key, reading.targets, at: reading.asOf)
            }
        }
    }

    private func isFresh(_ entry: CLIWorkspace, stats: PortStatsSource) -> Bool {
        guard data.cache.isFresh(MachineDataKeys.sites(entry.machine)),
              let refreshedAt = stats.state(for: entry.machine)?.refreshedAt else { return false }
        return Date().timeIntervalSince(refreshedAt) < data.portsTTL
    }

    /// The list from what is cached alone: the sites, and the poller's ports
    /// when it has any (a missing snapshot only means no ports yet).
    func cachedTargets(_ name: String, stats: PortStatsSource) -> (targets: [PreviewTarget], asOf: Date?)? {
        guard let entry = data.cachedEntry(name), let sites = data.cachedSites(machine: entry.machine) else {
            return nil
        }
        let state = stats.state(for: entry.machine)
        let targets = PreviewTargets.remote(
            workspace: name, user: entry.user, sites: sites.value.sites,
            ports: state?.snapshot?.ports ?? [], containers: state?.snapshot?.containers ?? [])
        let asOf = [sites.fetchedAt, state?.refreshedAt].compactMap { $0 }.min()
        return (targets, asOf)
    }

    private func setLoaded(_ key: String, _ targets: [PreviewTarget], at date: Date?) {
        if case let .loaded(current) = phases[key] {
            let merge = StableList.merge(old: current, new: targets)
            if merge.changed { phases[key] = .loaded(merge.list) }
        } else {
            phases[key] = .loaded(targets)
        }
        if refreshedAt[key] != date { refreshedAt[key] = date }
    }

    private func recomputeWorkspaces(onMachine machine: String?) {
        guard let stats else { return }
        for key in phases.keys where key.hasPrefix("ws:") {
            let name = String(key.dropFirst(3))
            guard machine == nil || data.cachedEntry(name)?.machine == machine,
                  let reading = cachedTargets(name, stats: stats) else { continue }
            setLoaded(key, reading.targets, at: reading.asOf)
        }
    }
}
