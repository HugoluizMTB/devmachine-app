import Foundation
import DevmachineCore

/// Reads what one workspace can preview: the sites its machine publishes for
/// it and the ports its user listens on, or what this Mac listens on.
struct PreviewTargetsService: Sendable {
    static let lsof = "/usr/sbin/lsof"

    let cli: DevmachineCLI?
    let localRunner: any CommandRunner

    init(cli: DevmachineCLI? = nil, localRunner: any CommandRunner = ProcessRunner()) {
        self.cli = cli
        self.localRunner = localRunner
    }

    func targets(for place: PreviewPlace, cachedStats: [String: StatsSnapshot]) throws -> [PreviewTarget] {
        switch place {
        case .thisMac:
            let output = try localRunner.run(
                executable: Self.lsof, args: ListeningPortsParser.arguments + ["-a", "-u", NSUserName()],
                environment: nil)
            return PreviewTargets.local(ListeningPortsParser.parse(output))
        case let .workspace(name):
            let cli = try self.cli ?? DevmachineCLI.resolve()
            guard let entry = try cli.listWorkspaces().first(where: { $0.name == name }) else {
                throw DevmachineCLIError.commandFailed("The CLI has no workspace named \(name).")
            }
            let sites = (try? cli.listExposures(machine: entry.machine).sites) ?? []
            let snapshot = try cachedStats[entry.machine]
                ?? StatsParser.parse(cli.run(machine: entry.machine, package: "devmachine-app", args: ["stats"]))
            return PreviewTargets.remote(
                workspace: name, user: entry.user, sites: sites, ports: snapshot?.ports ?? [],
                containers: snapshot?.containers ?? [])
        }
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

/// The Preview tab's list, per workspace, read when the tab shows and on
/// Refresh: nothing polls it.
@MainActor
final class PreviewTargetsStore: ObservableObject {
    static let shared = PreviewTargetsStore()

    enum Phase: Equatable {
        case loading
        case loaded([PreviewTarget])
        case failed(String)
    }

    @Published private(set) var phases: [String: Phase] = [:]

    private let service: PreviewTargetsService
    private var inFlight: Set<String> = []

    init(service: PreviewTargetsService = PreviewTargetsService()) {
        self.service = service
    }

    func phase(for place: PreviewPlace) -> Phase? { phases[place.key] }

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

    func load(_ place: PreviewPlace, cachedStats: [String: StatsSnapshot], force: Bool = false) {
        let key = place.key
        if DemoMode.isActive {
            phases[key] = .loaded(DemoData.previewTargets(for: place))
            return
        }
        guard !inFlight.contains(key) else { return }
        if !force, case .loaded = phases[key] { return }
        if case .loaded = phases[key] {} else { phases[key] = .loading }
        inFlight.insert(key)
        let service = self.service
        Task {
            let result = await Task.detached { Result { try service.targets(for: place, cachedStats: cachedStats) } }.value
            inFlight.remove(key)
            switch result {
            case let .success(targets): phases[key] = .loaded(targets)
            case let .failure(error): phases[key] = .failed(PackageGateMessage.friendly(for: error))
            }
        }
    }
}
