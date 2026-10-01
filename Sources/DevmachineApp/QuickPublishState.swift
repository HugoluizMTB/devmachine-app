import SwiftUI
import DevmachineCore

/// Drives the "Publish a port…" flow started from a remote workspace. The
/// sheet opens at once with the ports already known (the stats poller's
/// snapshot); when those are older than the ports TTL, fresh ones replace
/// them in the open sheet.
@MainActor
final class QuickPublishState: ObservableObject {
    @Published var workspace: String?
    @Published private(set) var ports: [PortSuggestion] = []
    @Published private(set) var portsAsOf: Date?
    @Published private(set) var isRefreshingPorts = false

    private let data: WorkspaceMachineData
    private let now: @MainActor () -> Date
    private var refreshTask: Task<Void, Never>?

    init(data: WorkspaceMachineData = .shared, now: @escaping @MainActor () -> Date = { Date() }) {
        self.data = data
        self.now = now
    }

    func start(workspace: String, stats: PortStatsSource) {
        refreshTask?.cancel()
        if DemoMode.isActive {
            ports = DemoData.publishSuggestions.ports
            portsAsOf = nil
            isRefreshingPorts = false
            self.workspace = workspace
            return
        }
        let cached = data.cachedPorts(workspace: workspace, stats: stats)
        ports = cached?.ports ?? []
        portsAsOf = cached?.asOf
        self.workspace = workspace

        let ttl = data.portsTTL
        let isFresh = cached?.asOf.map { now().timeIntervalSince($0) < ttl } ?? false
        guard !isFresh else {
            isRefreshingPorts = false
            return
        }
        isRefreshingPorts = true
        let data = self.data
        refreshTask = Task {
            let fresh = await data.refreshedPorts(workspace: workspace, stats: stats)
            guard !Task.isCancelled, self.workspace == workspace else { return }
            if let fresh {
                let merge = StableList.merge(old: self.ports, new: fresh.ports)
                if merge.changed { self.ports = merge.list }
                self.portsAsOf = fresh.asOf
            }
            self.isRefreshingPorts = false
        }
    }
}

extension View {
    /// Presents `AddSubdomainSheet` once `state.workspace` is set, preselected
    /// and pre-filled with that workspace's own ports.
    func quickPublishSheet(_ state: QuickPublishState, settings: AppSettings?, workspaces: [Workspace]) -> some View {
        sheet(isPresented: Binding(
            get: { state.workspace != nil },
            set: { if !$0 { state.workspace = nil } }
        )) {
            if let workspace = state.workspace, let settings {
                AddSubdomainSheet(
                    settings: settings, workspaces: workspaces, preselectedWorkspace: workspace,
                    suggestedPorts: state.ports,
                    suggestedLabel: workspace,
                    portsAsOf: state.portsAsOf,
                    isRefreshingPorts: state.isRefreshingPorts)
            }
        }
    }
}
