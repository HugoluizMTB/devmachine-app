import Foundation
import DevmachineCore

/// One read of the packages, the machines and workspaces they go on, and
/// what the lock says each one has applied.
struct PackagesSnapshot: Equatable, Sendable {
    var entries: [PackageEntry]
    var targets: [PackageTarget]
    var lock: PackagesLock?
    var cliVersion: SemanticVersion?
    var configDirectory: String?
    /// Each machine's `linux` or `macos`, for the machines the CLI has read.
    var platforms: [String: String] = [:]

    func statuses(for target: PackageTarget) -> [String: PackageStatus] {
        PackageStatusCheck.evaluate(entries: entries, target: target, lock: lock)
    }

    /// This Mac is `macos` even when the CLI does not say so; any other
    /// machine it never read is unknown.
    func platform(of target: PackageTarget) -> String? {
        if let reported = platforms[target.syncMachine] { return reported }
        return targets.contains(.machine(target.syncMachine, isSelf: true)) ? "macos" : nil
    }

    /// Whether `entry` runs on the picked machine and workspace. Only the
    /// picked ones of its own kind count; none picked means it fits.
    func systemFit(
        _ entry: PackageEntry, on focus: [PackageTarget], statuses: [PackageTarget: [String: PackageStatus]]
    ) -> PackageSystemFit {
        PackageAvailability.systemFit(
            platforms: entry.platforms,
            on: focus.filter { $0.scope == entry.scope }.map { target in
                (system: platform(of: target), installed: (statuses[target]?[entry.name] ?? .available).isInstalled)
            })
    }
}

enum PackagesReader {
    static func read(
        cli: DevmachineCLI, readLock: (String) -> LockFileRead = LockFileRead.read(directory:)
    ) throws -> PackagesSnapshot {
        let show = try cli.configShow()
        let entries = try cli.packages().map(\.entry)
        let version = (try? cli.version()).flatMap { SemanticVersion.first(in: $0) }
        let directory = try? cli.configPath().path
        let lock: PackagesLock? = directory.flatMap { directory in
            switch readLock(directory) {
            case .missing: return PackagesLock(machines: [:])
            case let .text(text): return PackagesLock.parse(text)
            case .unreadable: return nil
            }
        }
        let targets = show.machines.map { PackageTarget.machine($0.name, isSelf: $0.isSelf) }
            + show.workspaces.map { PackageTarget.workspace($0.name, machine: $0.machine) }
        let platforms = Dictionary(
            show.machines.compactMap { machine in machine.platform.map { (machine.name, $0) } },
            uniquingKeysWith: { first, _ in first })
        return PackagesSnapshot(
            entries: entries, targets: targets, lock: lock, cliVersion: version, configDirectory: directory,
            platforms: platforms)
    }

    static let liveRead: @Sendable () async throws -> PackagesSnapshot = {
        try await Task.detached { try read(cli: DevmachineCLI.resolve()) }.value
    }

    static let liveEdit: @Sendable ([String]) async throws -> Void = { arguments in
        try await Task.detached { try DevmachineCLI.resolve().runPackageEdit(arguments) }.value
    }
}

/// The Packages page's data: what each machine and workspace has, the
/// `packages add|rm` that change a selection, and the sync that applies it.
@MainActor
final class PackagesStore: ObservableObject {
    static let shared = PackagesStore()

    enum Phase: Equatable {
        case loading
        case loaded
        case failed(DMErrorState)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var snapshot: PackagesSnapshot?
    @Published private(set) var applying = false
    @Published var applyError: DMErrorState?

    private let read: @Sendable () async throws -> PackagesSnapshot
    private let edit: @Sendable ([String]) async throws -> Void
    private let jobs: @MainActor () -> MachineJobCenter?
    private let isDemo: @MainActor () -> Bool
    private var loading = false
    /// A load asked for while one runs: the configuration may have changed
    /// after that read started, so it reads once more when it ends.
    private var loadAgain = false
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(
        read: @escaping @Sendable () async throws -> PackagesSnapshot = PackagesReader.liveRead,
        edit: @escaping @Sendable ([String]) async throws -> Void = PackagesReader.liveEdit,
        jobs: @escaping @MainActor () -> MachineJobCenter? = { AppModel.shared?.jobs },
        isDemo: @escaping @MainActor () -> Bool = { DemoMode.isActive }
    ) {
        self.read = read
        self.edit = edit
        self.jobs = jobs
        self.isDemo = isDemo
        observer = NotificationCenter.default.addObserver(
            forName: ConfigDirectoryWatcher.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestLoad() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() async {
        if isDemo() { return }
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
                phase = .failed(DMErrorState(title: "Packages could not be read", message: error.localizedDescription))
            }
        } while loadAgain
    }

    func requestLoad() {
        Task { await load() }
    }

    /// Runs each `packages add|rm` in order, target by target, and stops at
    /// the first that fails; every target saved whole asks for its sync, and
    /// the job center merges two asks for the same machine into one.
    func apply(_ batch: PackageBatch) async -> Bool {
        guard !isDemo() else {
            applyError = DMErrorState(
                title: "Packages were not changed", message: "Demo mode never changes a configuration.")
            return false
        }
        guard !applying, !batch.isEmpty else { return false }
        applying = true
        defer { applying = false }
        let commands = batch.edits.flatMap { $0.changes.commands(target: $0.target) }
        let model = AppModel.shared
        let task = model?.beginTask(label: "Changing packages…", total: commands.count)
        var done = 0
        var saved: [SyncRequest] = []
        for item in batch.edits {
            for command in item.changes.commands(target: item.target) {
                do {
                    try await edit(command)
                } catch {
                    applyError = DMErrorState(
                        title: "\((["devmachine"] + command.prefix(3)).joined(separator: " ")) failed",
                        message: error.localizedDescription)
                    if let task { model?.dropTask(task) }
                    requestSyncs(saved)
                    await load()
                    return false
                }
                done += 1
                if let task { model?.setTask(task, completed: done) }
            }
            if let request = item.changes.syncRequest(target: item.target) { saved.append(request) }
        }
        if let task { model?.finishTask(task) }
        requestSyncs(saved)
        await load()
        return true
    }

    private func requestSyncs(_ requests: [SyncRequest]) {
        for request in requests {
            jobs()?.requestSync(request, onFinish: { [weak self] _ in self?.requestLoad() })
        }
    }

    /// Asks for the sync that applies what the configuration declares and
    /// the lock does not have yet, or still has after a removal.
    func syncPending(on target: PackageTarget) {
        guard let snapshot,
              let request = PackagePending.syncRequest(statuses: snapshot.statuses(for: target), target: target)
        else { return }
        jobs()?.requestSync(request, onFinish: { [weak self] _ in self?.requestLoad() })
    }

    /// Demo mode only: a fixed state, with no CLI behind it.
    func seedDemo(_ snapshot: PackagesSnapshot?) {
        self.snapshot = snapshot
        phase = .loaded
    }
}
