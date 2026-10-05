import Combine
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

/// Where a machine's Prepare stands, read from its job in the corner and
/// from the check after it. `inCorner` says the failure is that job's own,
/// so its log and Retry are there.
enum PrepareStatus: Equatable {
    case running
    case succeeded
    case failed(DMErrorState, inCorner: Bool)
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
        : NSClassFromString("XCTestCase") != nil
            ? MachineReadinessStore(read: { nil }, jobs: { nil })
            : MachineReadinessStore(read: { nil })

    @Published private(set) var snapshot: ReadinessSnapshot?
    @Published private(set) var states: [String: MachineReadiness] = [:]
    /// The corner job each machine's Prepare runs as.
    @Published private(set) var preparing: [String: UUID] = [:]
    /// A Prepare whose sync succeeded but left the machine unready.
    @Published private(set) var prepareFailure: [String: DMErrorState] = [:]
    @Published private var preparePhases: [String: MachineJobPhase] = [:]

    /// A sync just made a machine ready: its sessions and stats are read again.
    var onPrepared: ((String) -> Void)?
    /// The CLI's configuration changed on disk (a machine or workspace added
    /// or edited, a sync recorded in the lock).
    var onConfigurationChanged: (() -> Void)?

    private var read: @Sendable () async -> ReadinessSnapshot?
    private let jobs: @MainActor () -> MachineJobCenter?
    private var observed: [String: (failure: PackageCallFailure, lockStamp: String?)] = [:]
    /// The Prepare each machine last started. It outlives the corner card,
    /// so a check that ends after the card left still reports.
    private var prepareRun: [String: UUID] = [:]
    private var jobsWatch: AnyCancellable?
    private weak var watchedCenter: MachineJobCenter?
    private var checking = false
    private var lastCheck = Date.distantPast
    private var checkAgain = false
    private var watcher: ConfigDirectoryWatcher?
    private var reportObserver: NSObjectProtocol?

    init(
        read: @escaping @Sendable () async -> ReadinessSnapshot? = {
            await Task.detached { ReadinessReader.read(cli: { try DevmachineCLI.resolve() }) }.value
        },
        jobs: @escaping @MainActor () -> MachineJobCenter? = { AppModel.shared?.jobs },
        listensForReports: Bool = true
    ) {
        self.read = read
        self.jobs = jobs
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
        (snapshot?.machines ?? []).filter { state(for: $0).needsAttention || prepareStatus($0) != nil }
    }

    func prepareStatus(_ machine: String) -> PrepareStatus? {
        if let failure = prepareFailure[machine] { return .failed(failure, inCorner: false) }
        switch preparePhases[machine] {
        case .pending, .queued, .running: return .running
        case .succeeded: return .succeeded
        case let .failed(cause):
            return .failed(DMErrorState(title: "\(machine) was not prepared", cause: cause, details: ""), inCorner: true)
        case .cancelled, nil: return nil
        }
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

    /// Adds and syncs only `devmachine-app` as a job in the corner, which
    /// holds its log; the card reads where it stands from there.
    @discardableResult
    func prepare(_ machine: String) -> UUID? {
        guard canPrepareInApp, let center = jobs(), !isPreparing(machine, in: center) else { return nil }
        if let previous = preparing[machine] { center.dismiss(previous) }
        prepareFailure[machine] = nil
        let plan = MachineJobPlan(
            machine: machine, title: "Prepare \(machine)",
            steps: MachinePrepare.steps(machine: machine, declared: isDeclared(machine)))
        watch(center)
        var started: UUID?
        let id = center.run(plan) { [weak self] outcome in
            guard let started else { return }
            self?.prepareFinished(machine, job: started, outcome: outcome)
        }
        started = id
        preparing[machine] = id
        prepareRun[machine] = id
        followJobs(center.jobs)
        return id
    }

    /// A failed corner job runs again in place; a sync that left the machine
    /// unready starts a new Prepare.
    func retryPrepare(_ machine: String) {
        guard let center = jobs() else { return }
        if prepareFailure[machine] == nil, let id = preparing[machine], case .failed = center.job(id)?.phase {
            center.retry(id)
        } else {
            prepare(machine)
        }
    }

    func showPrepareInCorner(_ machine: String) {
        guard let center = jobs(), let id = preparing[machine], center.job(id)?.expanded == false else { return }
        center.toggleExpanded(id)
    }

    func dismissPrepare(_ machine: String) {
        if let id = preparing[machine] { jobs()?.dismiss(id) }
        preparing[machine] = nil
        prepareRun[machine] = nil
        prepareFailure[machine] = nil
        followJobs(jobs()?.jobs ?? [])
    }

    private func isPreparing(_ machine: String, in center: MachineJobCenter) -> Bool {
        center.jobs.contains { job in
            guard job.plan.machine == machine, job.plan.title == "Prepare \(machine)" else { return false }
            switch job.phase {
            case .pending, .queued, .running: return true
            case .succeeded, .failed, .cancelled: return false
            }
        }
    }

    private func prepareFinished(_ machine: String, job: UUID, outcome: MachineJobOutcome) {
        guard outcome == .succeeded, prepareRun[machine] == job else { return }
        observed[machine] = nil
        Task { [weak self] in
            guard let self else { return }
            await self.check()
            guard self.prepareRun[machine] == job else { return }
            let state = self.state(for: machine)
            guard state == .ready || state == .unknown else {
                self.prepareFailure[machine] = DMErrorState(
                    title: "\(machine) still isn't ready",
                    cause: "The sync finished, but the configuration does not show devmachine-app applied there.",
                    details: "")
                return
            }
            self.onPrepared?(machine)
        }
    }

    private func watch(_ center: MachineJobCenter) {
        guard watchedCenter !== center else { return }
        watchedCenter = center
        jobsWatch = center.$jobs.sink { [weak self] jobs in
            MainActor.assumeIsolated { self?.followJobs(jobs) }
        }
    }

    /// A Prepare job that left the corner (gone after its success, dismissed,
    /// cancelled) takes its card with it.
    private func followJobs(_ jobs: [MachineJob]) {
        var phases: [String: MachineJobPhase] = [:]
        var live: [String: UUID] = [:]
        for (machine, id) in preparing {
            guard let job = jobs.first(where: { $0.id == id }) else { continue }
            phases[machine] = job.phase
            live[machine] = id
        }
        if live != preparing { preparing = live }
        if phases != preparePhases { preparePhases = phases }
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
        let stale = prepareFailure.keys.filter { next[$0] == .ready }
        for machine in stale { prepareFailure[machine] = nil }
    }

    /// The CLI's folder is being watched. Before setup writes it there is
    /// nothing to watch, so each check tries again until there is.
    var isWatchingConfiguration: Bool { watcher?.isWatching ?? false }

    private func watch(_ directory: String) {
        guard watcher?.directory != directory || watcher?.isWatching != true else { return }
        watcher = ConfigDirectoryWatcher(directory: directory) { [weak self] in
            NotificationCenter.default.post(name: ConfigDirectoryWatcher.changed, object: nil)
            self?.onConfigurationChanged?()
            self?.requestCheck()
        }
    }

    #if DEBUG
    /// Demo walks only: a fixed state, with no real CLI behind it.
    func seedDemo(
        snapshot: ReadinessSnapshot, observed: [String: PackageCallFailure] = [:]
    ) {
        read = { snapshot }
        preparing = [:]
        prepareRun = [:]
        prepareFailure = [:]
        preparePhases = [:]
        self.snapshot = snapshot
        self.observed = observed.mapValues { ($0, snapshot.lock?.appliedAt) }
        recompute()
    }

    /// Demo walks only: a Prepare job in the corner, at one fixed moment.
    func seedDemoPrepare(_ machine: String, phase: MachineJobPhase, log: [String]) {
        guard let center = jobs() else { return }
        let plan = MachineJobPlan(
            machine: machine, title: "Prepare \(machine)",
            steps: MachinePrepare.steps(machine: machine, declared: isDeclared(machine)))
        var lines = JobLog()
        lines.append(contentsOf: log)
        let job = MachineJob(
            id: UUID(), plan: plan, phase: phase, log: lines, expanded: true,
            currentCommand: plan.steps.last.map { "devmachine " + $0.joined(separator: " ") })
        watch(center)
        center.seedDemo([job])
        preparing[machine] = job.id
        followJobs(center.jobs)
    }
    #endif
}

/// Watches the CLI's configuration folder. The CLI saves `config.yml` and
/// `packages.lock` by renaming a temporary file, which the folder sees;
/// an editor that writes `config.yml` in place is seen on the file itself.
/// Bursts settle for a second before one callback.
@MainActor
final class ConfigDirectoryWatcher {
    /// Posted on the main thread each time the readiness store's watcher
    /// sees the folder change, for every page that reads the configuration.
    static let changed = Notification.Name("DevmachineConfigDirectoryChanged")

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
