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
/// before the CLI's `config.yml` exists: then there is no machine. An older
/// CLI fails every `machines`/`packages` call then, so none is made; one
/// that adds without a terminal (`MachineUnattendedAdd`) lists the latest
/// release's packages, which the first machine can start with.
struct MachinesSnapshot: Equatable, Sendable {
    var hasConfiguration: Bool
    var machines: [ConfiguredMachine]
    var packages: [CLIPackage]
    var cliVersion: SemanticVersion?

    init(
        hasConfiguration: Bool, machines: [ConfiguredMachine], packages: [CLIPackage],
        cliVersion: SemanticVersion? = nil
    ) {
        self.hasConfiguration = hasConfiguration
        self.machines = machines
        self.packages = packages
        self.cliVersion = cliVersion
    }

    static let none = MachinesSnapshot(hasConfiguration: false, machines: [], packages: [])

    var addsWithoutTerminal: Bool { MachineUnattendedAdd.isSupported(cliVersion: cliVersion) }
}

enum MachinesReader {
    static func read(
        cli: DevmachineCLI,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> MachinesSnapshot {
        let directory = try cli.configPath().path
        let version = (try? cli.version()).flatMap { SemanticVersion.first(in: $0) }
        guard fileExists((directory as NSString).appendingPathComponent(AppSettings.opsRepoMarker)) else {
            guard MachineUnattendedAdd.isSupported(cliVersion: version) else {
                return MachinesSnapshot(hasConfiguration: false, machines: [], packages: [], cliVersion: version)
            }
            // The latest release is read over the network; without one the
            // wizard still offers essentials, so a failure is not an error.
            let packages = (try? cli.packages()) ?? []
            return MachinesSnapshot(hasConfiguration: false, machines: [], packages: packages, cliVersion: version)
        }
        let packages = try cli.packages()
        let machines = try cli.listConfigMachines().map { machine in
            ConfiguredMachine(
                name: machine.name, hosts: machine.hosts, adminUser: machine.adminUser, port: machine.port,
                workspaces: machine.workspaces,
                packages: machine.packages
                    ?? packages.filter { $0.isInstalled(onMachine: machine.name) }.map(\.name),
                isSelf: machine.isSelf)
        }
        return MachinesSnapshot(hasConfiguration: true, machines: machines, packages: packages, cliVersion: version)
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
    /// A load asked for while one runs: the configuration may have changed
    /// after that read started, so it reads once more when it ends.
    private var loadAgain = false

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

    /// The pinned release's workspace packages, which decide the harnesses
    /// that can be turned on; nil until a read listed any.
    var workspacePackageNames: Set<String>? {
        let names = (snapshot?.packages ?? []).filter { $0.scope == "workspace" }.map(\.name)
        return names.isEmpty ? nil : Set(names)
    }

    var packageCards: [MachinePackageCard] {
        MachinePackageCatalog.cards(from: (snapshot?.packages ?? []).map(\.info))
    }

    func load() async {
        if DemoMode.isActive {
            if snapshot == nil { seedDemo(DemoData.machinesSnapshot) }
            return
        }
        if loading {
            loadAgain = true
            return
        }
        loading = true
        defer { loading = false }
        if snapshot == nil { phase = .loading }
        repeat {
            loadAgain = false
            do {
                let next = try await read()
                if snapshot != next { snapshot = next }
                phase = .loaded
            } catch {
                phase = .failed(DMErrorState(
                    title: "Could not read the machines", message: error.localizedDescription))
            }
        } while loadAgain
    }

    func requestLoad() {
        Task { await load() }
    }

    func removeMachine(_ name: String) async {
        guard removing == nil else { return }
        guard !DemoMode.isActive else {
            removalError = DMErrorState(title: "Could not remove \(name)", message: "Demo mode never removes a machine.")
            return
        }
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
