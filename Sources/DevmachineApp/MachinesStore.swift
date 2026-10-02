import Foundation
import DevmachineCore

/// One machine in the CLI's configuration, with the packages that name it.
struct ConfiguredMachine: Equatable, Identifiable, Sendable {
    let name: String
    let hosts: [String]
    let adminUser: String
    let port: Int
    let workspaces: [String]
    let packages: [String]
    let isSelf: Bool

    var id: String { name }
}

/// What one read of the configuration found. `hasConfiguration` is false
/// before the CLI's `config.yml` exists: then there is no machine, and every
/// `machines`/`packages` call fails, so none is made.
struct MachinesSnapshot: Equatable, Sendable {
    var hasConfiguration: Bool
    var machines: [ConfiguredMachine]
    var packages: [CLIPackage]

    static let none = MachinesSnapshot(hasConfiguration: false, machines: [], packages: [])
}

enum MachinesReader {
    static func read(
        cli: DevmachineCLI,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> MachinesSnapshot {
        let directory = try cli.configPath().path
        guard fileExists((directory as NSString).appendingPathComponent(AppSettings.opsRepoMarker)) else {
            return .none
        }
        let packages = try cli.packages()
        let machines = try cli.listConfigMachines().map { machine in
            ConfiguredMachine(
                name: machine.name, hosts: machine.hosts, adminUser: machine.adminUser, port: machine.port,
                workspaces: machine.workspaces,
                packages: packages.filter { $0.isInstalled(onMachine: machine.name) }.map(\.name),
                isSelf: machine.isSelf)
        }
        return MachinesSnapshot(hasConfiguration: true, machines: machines, packages: packages)
    }
}

/// The machines Settings lists, the sidebar's "Add a machine" rule and the
/// wizard's package cards, from one read of the CLI.
@MainActor
final class MachinesStore: ObservableObject {
    static let shared = MachinesStore()

    enum Phase: Equatable {
        case loading
        case loaded
        case failed(DMErrorState)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var snapshot: MachinesSnapshot?
    @Published private(set) var removing: String?
    @Published var removalError: DMErrorState?

    private let read: @Sendable () async throws -> MachinesSnapshot
    private let remove: @Sendable (String) async throws -> Void
    private var loading = false

    init(
        read: @escaping @Sendable () async throws -> MachinesSnapshot = {
            try await Task.detached { try MachinesReader.read(cli: DevmachineCLI.resolve()) }.value
        },
        remove: @escaping @Sendable (String) async throws -> Void = { name in
            try await Task.detached { try DevmachineCLI.resolve().removeMachine(name) }.value
        }
    ) {
        self.read = read
        self.remove = remove
    }

    var machines: [ConfiguredMachine] { snapshot?.machines ?? [] }

    /// Nil until the first read answers, so the sidebar never offers a
    /// machine to somebody who has one that is still loading.
    var remoteMachineNames: [String]? {
        snapshot.map { $0.machines.filter { !$0.isSelf }.map(\.name) }
    }

    var packageCards: [MachinePackageCard] {
        MachinePackageCatalog.cards(from: (snapshot?.packages ?? []).map(\.info))
    }

    func load() async {
        if DemoMode.isActive {
            if snapshot == nil { seedDemo(DemoData.machinesSnapshot) }
            return
        }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if snapshot == nil { phase = .loading }
        do {
            let next = try await read()
            if snapshot != next { snapshot = next }
            phase = .loaded
        } catch {
            phase = .failed(DMErrorState(
                title: "Could not read the machines", message: error.localizedDescription))
        }
    }

    func requestLoad() {
        Task { await load() }
    }

    func removeMachine(_ name: String) async {
        guard removing == nil else { return }
        removing = name
        defer { removing = nil }
        do {
            try await remove(name)
            await load()
        } catch {
            removalError = DMErrorState(title: "Could not remove \(name)", message: error.localizedDescription)
        }
    }

    /// Demo mode only: a fixed configuration, with no CLI behind it.
    func seedDemo(_ snapshot: MachinesSnapshot?) {
        self.snapshot = snapshot
        phase = .loaded
    }
}
