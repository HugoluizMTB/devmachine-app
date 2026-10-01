import Foundation
import DevmachineCore

/// The stats poller, as the ports readers see it: what it holds now, and
/// one read through its own schedule when that is too old.
@MainActor
protocol PortStatsSource: AnyObject {
    func state(for machine: String?) -> MachineStatsState?
    func freshSnapshot(_ machine: String, maxAge: TimeInterval) async -> StatsSnapshot?
}

extension StatsStore: PortStatsSource {}

/// A workspace's own listening ports, and when they were read.
struct PortsReading: Equatable {
    var ports: [PortSuggestion]
    var asOf: Date?
}

/// What one workspace's machine has, read local-first: which machine and
/// user the workspace is (the cached `workspaces list`), its ports (the
/// stats poller's snapshot) and its published sites (the cached `expose
/// list`). Publish a port… and Preview read it at once; a session's
/// Context warms it so both open with something to show.
@MainActor
final class WorkspaceMachineData {
    static let shared = WorkspaceMachineData(cache: .shared)

    let cache: DataCache
    private let listWorkspaces: @Sendable () throws -> [CLIWorkspace]
    private let listExposures: @Sendable (String) throws -> ExposureListing

    init(
        cache: DataCache = DataCache(),
        listWorkspaces: @escaping @Sendable () throws -> [CLIWorkspace] = {
            try DevmachineCLI.resolve().listWorkspaces()
        },
        listExposures: @escaping @Sendable (String) throws -> ExposureListing = {
            try DevmachineCLI.resolve().listExposures(machine: $0)
        }
    ) {
        self.cache = cache
        self.listWorkspaces = listWorkspaces
        self.listExposures = listExposures
    }

    var portsTTL: TimeInterval { cache.policy.ttl(for: .ports) }

    func cachedEntry(_ workspace: String) -> CLIWorkspace? {
        cache.cached(MachineDataKeys.workspaces)?.value.first { $0.name == workspace }
    }

    /// The workspace's entry, read from the CLI only when the cached list is
    /// older than its TTL or missing it.
    func entry(_ workspace: String) async -> CLIWorkspace? {
        let listWorkspaces = self.listWorkspaces
        let key = MachineDataKeys.workspaces
        if cache.isFresh(key), let cached = cachedEntry(workspace) { return cached }
        let list = try? await cache.value(key, force: cache.isFresh(key)) { try listWorkspaces() }
        return list?.first { $0.name == workspace } ?? cachedEntry(workspace)
    }

    func cachedPorts(workspace: String, stats: PortStatsSource) -> PortsReading? {
        guard let entry = cachedEntry(workspace),
              let state = stats.state(for: entry.machine), let snapshot = state.snapshot else { return nil }
        return PortsReading(
            ports: PublishSuggestions.ports(forUser: entry.user, ports: snapshot.ports, containers: snapshot.containers),
            asOf: state.refreshedAt)
    }

    func refreshedPorts(workspace: String, stats: PortStatsSource) async -> PortsReading? {
        guard let entry = await entry(workspace) else { return nil }
        _ = await stats.freshSnapshot(entry.machine, maxAge: portsTTL)
        return cachedPorts(workspace: workspace, stats: stats)
    }

    func cachedSites(machine: String) -> Cached<ExposureListing>? {
        cache.cached(MachineDataKeys.sites(machine))
    }

    func sites(machine: String, force: Bool = false) async throws -> ExposureListing {
        let listExposures = self.listExposures
        return try await cache.value(MachineDataKeys.sites(machine), force: force) {
            try listExposures(machine)
        }
    }

    /// Reads only what is older than its TTL; what is fresh costs nothing.
    func warm(workspace: String, stats: PortStatsSource) async {
        guard !DemoMode.isActive, let entry = await entry(workspace) else { return }
        _ = try? await sites(machine: entry.machine)
        _ = await stats.freshSnapshot(entry.machine, maxAge: portsTTL)
    }
}
