import Foundation
import DevmachineCore

/// Everything one readiness check read from the CLI and its configuration
/// folder. A part that could not be read stays nil, and the check fails open
/// on it.
struct ReadinessSnapshot: Equatable, Sendable {
    var machines: [String] = []
    var declared: [String: Bool]?
    var lock: PackagesLock?
    var workspaceMachines: [String: String] = [:]
    var cliVersion: SemanticVersion?
    var sshAliasesWritten: Bool?
    var configDirectory: String?

    func applied(_ machine: String) -> Bool? {
        lock.map { $0.has(MachinePrepare.package, onMachine: machine) }
    }
}

/// What reading `packages.lock` found. A missing lock is the CLI's ordinary
/// first state, a machine nothing was ever synced to; an unreadable one says
/// nothing.
enum LockFileRead: Equatable, Sendable {
    case missing
    case text(String)
    case unreadable

    static func read(directory: String) -> LockFileRead {
        let path = (directory as NSString).appendingPathComponent(PackagesLock.fileName)
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .unreadable }
        return .text(text)
    }
}

enum ReadinessReader {
    static func read(
        cli: () throws -> DevmachineCLI,
        readLock: (String) -> LockFileRead = LockFileRead.read(directory:)
    ) -> ReadinessSnapshot? {
        guard let instance = try? cli(), let show = try? instance.configShow() else { return nil }
        var snapshot = ReadinessSnapshot()
        snapshot.machines = show.machines.filter { !$0.isSelf }.map(\.name)
        snapshot.workspaceMachines = Dictionary(
            show.workspaces.map { ($0.name, $0.machine) }, uniquingKeysWith: { first, _ in first })
        if let packages = try? instance.packages() {
            let devmachineApp = packages.first { $0.name == MachinePrepare.package }
            snapshot.declared = Dictionary(uniqueKeysWithValues: snapshot.machines.map {
                ($0, devmachineApp?.isInstalled(onMachine: $0) ?? false)
            })
        }
        if let directory = try? instance.configPath().path {
            snapshot.configDirectory = directory
            switch readLock(directory) {
            case .missing: snapshot.lock = PackagesLock(machines: [:])
            case let .text(text): snapshot.lock = PackagesLock.parse(text)
            case .unreadable: snapshot.lock = nil
            }
        }
        snapshot.cliVersion = (try? instance.version()).flatMap { SemanticVersion.first(in: $0) }
        snapshot.sshAliasesWritten = (try? instance.aliasListing())?.sshAliases
        return snapshot
    }
}

enum PreparePhase: Equatable {
    case running
    case succeeded
    case failed(DMErrorState)
}

struct PrepareJob: Equatable {
    var phase: PreparePhase
    var output: [String]
}

/// Whether each configured machine has `devmachine-app`, and the one-click
/// Prepare that puts it there. Checked at launch, whenever the CLI's
/// configuration folder changes, and whenever a call into the package fails
/// because it is missing or too old.
@MainActor
final class MachineReadinessStore: ObservableObject {
    /// Under XCTest the shared store reads nothing: a test that posts a
    /// package failure must never reach the real CLI or its configuration.
    /// Demo mode reads nothing either; a walk hands it a fixed state.
    static let shared = NSClassFromString("XCTestCase") == nil && !DemoMode.isActive
        ? MachineReadinessStore()
        : MachineReadinessStore(read: { nil }, runner: ProcessJobRunner(cli: {
            throw DevmachineCLIError.commandFailed("no CLI under tests or in demo mode")
        }))

    @Published private(set) var snapshot: ReadinessSnapshot?
    @Published private(set) var states: [String: MachineReadiness] = [:]
    @Published private(set) var jobs: [String: PrepareJob] = [:]

    /// A sync just made a machine ready: its sessions and stats are read again.
    var onPrepared: ((String) -> Void)?
    /// The CLI's configuration changed on disk (a machine or workspace added
    /// or edited, a sync recorded in the lock).
    var onConfigurationChanged: (() -> Void)?

    private var read: @Sendable () async -> ReadinessSnapshot?
    private var runner: any MachineJobRunning
    private var observed: [String: (failure: PackageCallFailure, lockStamp: String?)] = [:]
    /// The run each machine's card belongs to; a run that was replaced (a
    /// dismissed card, a new run) writes nothing when it ends.
    private var runs: [String: UUID] = [:]
    private var checking = false
    private var lastCheck = Date.distantPast
    private var checkAgain = false
    private var watcher: ConfigDirectoryWatcher?
    private var reportObserver: NSObjectProtocol?

    init(
        read: @escaping @Sendable () async -> ReadinessSnapshot? = {
            await Task.detached { ReadinessReader.read(cli: { try DevmachineCLI.resolve() }) }.value
        },
        runner: any MachineJobRunning = ProcessJobRunner(),
        listensForReports: Bool = true
    ) {
        self.read = read
        self.runner = runner
        guard listensForReports else { return }
        reportObserver = NotificationCenter.default.addObserver(
            forName: PackageCallReports.notification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let report = PackageCallReports.report(from: notification) else { return }
            MainActor.assumeIsolated { self?.observe(report) }
        }
    }

    func state(for machine: String) -> MachineReadiness {
        states[machine] ?? .unknown
    }

    func machine(forWorkspace workspace: String) -> String? {
        snapshot?.workspaceMachines[workspace]
    }

    func isDeclared(_ machine: String) -> Bool {
        snapshot?.declared?[machine] ?? false
    }

    var canPrepareInApp: Bool {
        MachinePrepare.canPrepareInApp(cliVersion: snapshot?.cliVersion)
    }

    /// Machines that need the person, in configuration order.
    var machinesNeedingAttention: [String] {
        (snapshot?.machines ?? []).filter { state(for: $0).needsAttention || jobs[$0] != nil }
    }

    func requestCheck() {
        guard !DemoMode.isActive else { return }
        Task { await check() }
    }

    /// Coming back to the app is a cheap moment to notice a change made in a
    /// terminal, at most once every half minute.
    func requestCheckIfStale(now: Date = Date()) {
        guard snapshot != nil, now.timeIntervalSince(lastCheck) > 30 else { return }
        requestCheck()
    }

    /// One read at a time; a request that arrives during one runs once more
    /// after it, so the last change on disk is always the one shown.
    func check() async {
        if checking {
            checkAgain = true
            return
        }
        checking = true
        lastCheck = Date()
        repeat {
            checkAgain = false
            let next = await read()
            apply(next)
        } while checkAgain
        checking = false
    }

    func observe(_ report: PackageCallReports.Report) {
        guard let failure = PackageCallFailure.classify(report.detail) else { return }
        let named = report.machine
            ?? PackageCallFailure.machine(in: report.detail)
            ?? report.workspace.flatMap { self.machine(forWorkspace: $0) }
        guard let machine = named, snapshot?.machines.contains(machine) ?? true else { return }
        observed[machine] = (failure, snapshot?.lock?.appliedAt)
        recompute()
        requestCheck()
    }

    func prepare(_ machine: String) async {
        guard canPrepareInApp, jobs[machine]?.phase != .running else { return }
        let steps = MachinePrepare.steps(machine: machine, declared: isDeclared(machine))
        let run = UUID()
        runs[machine] = run
        jobs[machine] = PrepareJob(phase: .running, output: [])
        let task = AppModel.shared?.beginTask(label: "Preparing \(machine)…", total: steps.count)
        let sink = ProcessOutputSink { [weak self] lines in
            guard self?.runs[machine] == run, var job = self?.jobs[machine], job.output.count < lines.count
            else { return }
            job.output = lines
            self?.jobs[machine] = job
        }
        let succeeded = await runSteps(steps, machine: machine, run: run, task: task, sink: sink)
        if let task {
            if succeeded { AppModel.shared?.finishTask(task) } else { AppModel.shared?.dropTask(task) }
        }
    }

    private func runSteps(
        _ steps: [[String]], machine: String, run: UUID, task: UUID?, sink: ProcessOutputSink
    ) async -> Bool {
        for (index, arguments) in steps.enumerated() {
            sink.receive("$ devmachine " + arguments.joined(separator: " "))
            let status: Int32
            do {
                status = try await runner.run(arguments: arguments, output: sink.receive)
            } catch {
                fail(machine, run: run, lines: sink.snapshot, fallback: error.localizedDescription)
                return false
            }
            guard status == 0 else {
                fail(machine, run: run, lines: sink.snapshot, fallback: "devmachine exited with status \(status).")
                return false
            }
            if let task { AppModel.shared?.setTask(task, completed: index + 1) }
        }

        guard runs[machine] == run else { return false }
        observed[machine] = nil
        await check()
        let lines = sink.snapshot
        guard runs[machine] == run else { return false }
        guard state(for: machine) == .ready || state(for: machine) == .unknown else {
            jobs[machine] = PrepareJob(phase: .failed(DMErrorState(
                title: "\(machine) still isn't ready",
                cause: "The sync finished, but the configuration does not show devmachine-app applied there.",
                details: lines.joined(separator: "\n"))), output: lines)
            return false
        }
        jobs[machine] = PrepareJob(phase: .succeeded, output: lines)
        onPrepared?(machine)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.successCardSeconds * 1_000_000_000)
            if self?.runs[machine] == run, self?.jobs[machine]?.phase == .succeeded { self?.jobs[machine] = nil }
        }
        return true
    }

    private static let successCardSeconds: UInt64 = 8

    func dismissJob(_ machine: String) {
        jobs[machine] = nil
        runs[machine] = nil
    }

    private func fail(_ machine: String, run: UUID, lines: [String], fallback: String) {
        guard runs[machine] == run else { return }
        let cause = MachinePrepare.failureCause(lines) ?? FailureCause(message: fallback)?.summary ?? fallback
        jobs[machine] = PrepareJob(phase: .failed(DMErrorState(
            title: "\(machine) was not prepared",
            cause: cause,
            details: lines.isEmpty ? fallback : lines.joined(separator: "\n"))), output: lines)
    }

    private func apply(_ next: ReadinessSnapshot?) {
        let stamp = next?.lock?.appliedAt
        observed = observed.filter { $0.value.lockStamp == stamp || next?.lock == nil }
        if snapshot != next { snapshot = next }
        recompute()
        if let directory = next?.configDirectory { watch(directory) }
    }

    private func recompute() {
        guard let snapshot else {
            if !states.isEmpty { states = [:] }
            return
        }
        var next: [String: MachineReadiness] = [:]
        for machine in snapshot.machines {
            next[machine] = ReadinessCheck.evaluate(
                declared: snapshot.declared?[machine],
                applied: snapshot.applied(machine),
                observed: observed[machine]?.failure)
        }
        if states != next { states = next }
    }

    /// The CLI's folder is being watched. Before setup writes it there is
    /// nothing to watch, so each check tries again until there is.
    var isWatchingConfiguration: Bool { watcher?.isWatching ?? false }

    private func watch(_ directory: String) {
        guard watcher?.directory != directory || watcher?.isWatching != true else { return }
        watcher = ConfigDirectoryWatcher(directory: directory) { [weak self] in
            self?.onConfigurationChanged?()
            self?.requestCheck()
        }
    }

    #if DEBUG
    /// Demo walks only: a fixed state, with no real CLI behind it.
    func seedDemo(
        snapshot: ReadinessSnapshot, observed: [String: PackageCallFailure] = [:],
        afterPrepare: ReadinessSnapshot? = nil, runner: (any MachineJobRunning)? = nil
    ) {
        let next = afterPrepare ?? snapshot
        read = { next }
        if let runner { self.runner = runner }
        jobs = [:]
        runs = [:]
        self.snapshot = snapshot
        self.observed = observed.mapValues { ($0, snapshot.lock?.appliedAt) }
        recompute()
    }

    func seedDemoJob(_ machine: String, _ job: PrepareJob?) {
        jobs[machine] = job
    }
    #endif
}

/// Watches the CLI's configuration folder. The CLI saves `config.yml` and
/// `packages.lock` by renaming a temporary file, which the folder sees;
/// an editor that writes `config.yml` in place is seen on the file itself.
/// Bursts settle for a second before one callback.
@MainActor
final class ConfigDirectoryWatcher {
    let directory: String
    private let onChange: @MainActor () -> Void
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(directory: String, onChange: @escaping @MainActor () -> Void) {
        self.directory = directory
        self.onChange = onChange
        folderSource = source(directory)
        watchConfigFile()
    }

    /// False when the folder did not exist when the watcher was made.
    var isWatching: Bool { folderSource != nil }

    deinit {
        folderSource?.cancel()
        fileSource?.cancel()
    }

    private func watchConfigFile() {
        fileSource?.cancel()
        fileSource = source((directory as NSString).appendingPathComponent("config.yml"))
    }

    private func source(_ path: String) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.watchConfigFile()
                self?.onChange()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
