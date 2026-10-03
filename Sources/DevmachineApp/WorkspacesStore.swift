import Foundation
import DevmachineCore

/// What one read of the workspaces found: the CLI's list, and the lock that
/// says what the last sync applied.
struct WorkspacesSnapshot: Equatable, Sendable {
    var workspaces: [WorkspaceSummary]
    var lock: PackagesLock?
    /// `defaults.workspace`, nil from a CLI older than `WorkspaceJSON`.
    var defaults: [String]?
    /// The configuration's top-level login answers.
    var sharing: [String: String] = [:]
    /// The CLI reports each workspace's login answers, so Edit can change them.
    var reportsSharing = false

    static let none = WorkspacesSnapshot(workspaces: [], lock: nil)
}

enum WorkspacesReader {
    /// Before `config.yml` exists `workspaces list` fails: there is simply
    /// no workspace yet.
    static func read(
        cli: DevmachineCLI,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        readLock: (String) -> LockFileRead = LockFileRead.read(directory:)
    ) throws -> WorkspacesSnapshot {
        let directory = try cli.configPath().path
        guard fileExists((directory as NSString).appendingPathComponent(AppSettings.opsRepoMarker)) else {
            return .none
        }
        let lock: PackagesLock?
        switch readLock(directory) {
        case .missing: lock = PackagesLock(machines: [:])
        case let .text(text): lock = PackagesLock.parse(text)
        case .unreadable: lock = nil
        }
        var snapshot = WorkspacesSnapshot(workspaces: try cli.workspaceSummaries(), lock: lock)
        let version = (try? cli.version()).flatMap { SemanticVersion.first(in: $0) }
        if WorkspaceJSON.isSupported(cliVersion: version), let show = try? cli.configShow() {
            snapshot.defaults = show.defaultWorkspacePackages ?? []
            snapshot.sharing = show.credentials ?? [:]
            snapshot.reportsSharing = true
        }
        return snapshot
    }
}

/// The Workspaces page's state, kept for the app's life so leaving the page
/// mid-run and coming back finds the run where it was. Every change is a
/// `devmachine` command shown first and run in the background
/// (`MachineStepRunner`), only after the person confirms it.
@MainActor
final class WorkspacesStore: ObservableObject {
    /// Demo mode reads a fixed list, with no CLI behind it.
    static let shared = DemoMode.isActive
        ? WorkspacesStore(read: { DemoData.workspacesSnapshot }, onChanged: {})
        : WorkspacesStore()

    enum Phase: Equatable {
        case loading
        case loaded
        case failed(DMErrorState)
    }

    struct MachineGroup: Equatable, Identifiable {
        let machine: String
        let workspaces: [WorkspaceSummary]
        var id: String { machine }
    }

    static let demoRefusal = "Demo mode never changes a workspace."

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var snapshot: WorkspacesSnapshot?
    /// Nil shows the list; anything else is a flow on screen.
    @Published var flow: WorkspaceFlow?
    let runner: MachineStepRunner
    let machines: MachinesStore
    private let read: @Sendable () async throws -> WorkspacesSnapshot
    private let loadMachines: Bool
    private let codingAgents: @MainActor (Set<String>?) -> CodingAgentPackages
    private let onChanged: @MainActor () -> Void

    init(
        machines: MachinesStore = .shared,
        runner: MachineStepRunner = MachineStepRunner(),
        read: @escaping @Sendable () async throws -> WorkspacesSnapshot = {
            try await Task.detached { try WorkspacesReader.read(cli: DevmachineCLI.resolve()) }.value
        },
        loadMachines: Bool = true,
        codingAgents: @escaping @MainActor (Set<String>?) -> CodingAgentPackages = { available in
            HarnessSettingsFacade().codingAgentPackages(
                for: SettingsStore.shared.settings ?? .empty, available: available)
        },
        onChanged: @escaping @MainActor () -> Void = { WorkspacesStore.reloadEverything() }
    ) {
        self.machines = machines
        self.runner = runner
        self.read = read
        self.loadMachines = loadMachines
        self.codingAgents = codingAgents
        self.onChanged = onChanged
    }

    var workspaces: [WorkspaceSummary] { snapshot?.workspaces ?? [] }

    /// Every machine that holds a workspace, in the configuration's order,
    /// then any machine the list names that the configuration does not.
    var groups: [MachineGroup] {
        var order = machines.machines.map(\.name)
        for workspace in workspaces where !order.contains(workspace.machine) {
            order.append(workspace.machine)
        }
        return order.compactMap { machine in
            let held = workspaces.filter { $0.machine == machine }
            return held.isEmpty ? nil : MachineGroup(machine: machine, workspaces: held)
        }
    }

    /// The machines a workspace can go on: never this Mac's `self` machine.
    var machineChoices: [WorkspaceMachineChoice] {
        machines.machines.filter { !$0.isSelf }.map {
            WorkspaceMachineChoice(name: $0.name, adminUser: $0.adminUser.isEmpty ? "root" : $0.adminUser)
        }
    }

    /// Coding agents only for the harnesses turned on in Settings →
    /// Harnesses; one the workspace already has stays, so it can be taken off.
    var packageCards: [MachinePackageCard] {
        WorkspacePackageCatalog.cards(
            from: (machines.snapshot?.packages ?? []).map(\.info), keeping: flow?.current?.packages ?? [],
            hiding: codingAgents(machines.workspacePackageNames).hidden, defaults: defaults)
    }

    /// The configured `defaults.workspace` on CLI 0.7.29+, else the setup's.
    var defaults: [String] { snapshot?.defaults ?? WorkspacePackageCatalog.cliDefaults }
    var knowsDefaults: Bool { snapshot?.defaults != nil }
    var reportsSharing: Bool { snapshot?.reportsSharing ?? false }

    /// The logins the edited workspace's packages use.
    var logins: [WorkspaceLogin] {
        guard let flow else { return [] }
        let declared = Dictionary(
            (machines.snapshot?.packages ?? []).map { ($0.name, $0.credentials ?? []) }, uniquingKeysWith: { a, _ in a })
        return WorkspaceLogin.logins(
            packages: [WorkspacePackageCatalog.account] + flow.packages, declared: declared,
            configuration: snapshot?.sharing ?? [:])
    }

    /// A typed value the CLI would store as text where a number is meant.
    var variableProblems: [String] {
        guard let flow else { return [] }
        return variables.flatMap { package, declared in
            declared.compactMap { $0.problem(flow.settingValue("\(package).\($0.name)")) }
        }
    }

    var canContinue: Bool {
        (flow?.canAdvance ?? false) && variableProblems.isEmpty
    }

    /// The variables each of the edited workspace's packages declares.
    var variables: [(package: String, variables: [PackageVariable])] {
        guard let flow else { return [] }
        let info = Dictionary(
            (machines.snapshot?.packages ?? []).map { ($0.name, $0.variables ?? []) }, uniquingKeysWith: { a, _ in a })
        return flow.packages.compactMap { package in
            let declared = info[package] ?? []
            return declared.isEmpty ? nil : (package, declared)
        }
    }

    var noCodingAgentOn: Bool {
        codingAgents(machines.workspacePackageNames).offered.isEmpty
    }

    func syncState(_ workspace: WorkspaceSummary) -> WorkspaceSyncState {
        WorkspaceSync.state(workspace: workspace.name, packages: workspace.packages, lock: snapshot?.lock)
    }

    func workspace(_ name: String) -> WorkspaceSummary? {
        workspaces.first { $0.name == name }
    }

    var isRunning: Bool { runner.phase == .running }

    func load() async {
        if loadMachines { await machines.load() }
        if snapshot == nil { phase = .loading }
        do {
            let next = try await read()
            if snapshot != next { snapshot = next }
            phase = .loaded
        } catch {
            phase = .failed(DMErrorState(title: "Could not read the workspaces", message: error.localizedDescription))
        }
    }

    /// The page came back: a finished run gives way to the list.
    func openPage() {
        guard !isRunning, flow?.stage == .run, runner.phase == .succeeded else { return }
        close()
    }

    /// A request while a new workspace is already being typed keeps it.
    func startNew() async {
        if case .new = flow?.action, flow?.stage != .run { return }
        guard !isRunning else { return }
        if loadMachines { await machines.load() }
        start(.new(
            machines: machineChoices, existingWorkspaces: workspaces.map(\.name),
            packages: WorkspacePackageCatalog.preselected(from: packageCards, defaults: defaults)))
    }

    func startEdit(_ name: String) {
        guard let workspace = workspace(name) else { return }
        start(.edit(workspace))
    }

    func startForget(_ name: String) {
        guard let workspace = workspace(name) else { return }
        start(.forget(workspace))
    }

    func startDestroy(_ name: String) {
        guard let workspace = workspace(name) else { return }
        start(.destroy(workspace))
    }

    private func start(_ next: WorkspaceFlow) {
        guard !isRunning else { return }
        runner.reset()
        flow = next
    }

    /// Cancel, Close and Done: back to the list, unless a run is going.
    func close() {
        guard !isRunning else { return }
        runner.reset()
        flow = nil
    }

    func next() {
        flow?.next()
    }

    func back() {
        flow?.back()
    }

    /// Runs the flow's commands; the page asks first.
    func run() async {
        guard var current = flow, !isRunning else { return }
        if current.stage != .run {
            guard current.canAdvance else { return }
            current.next()
            if current.stage != .run { current.next() }
            flow = current
        }
        BugReportEnvironment.typedWorkspaces = [current.name]
        BugReportEnvironment.typedMachines = [current.machine]
        await runner.run(
            current.plan, inTerminal: false, label: Self.label(current.action),
            demoRefusal: Self.demoRefusal)
        if runner.phase == .succeeded || current.plan.contains(where: { runner.status(of: $0) == .done }) {
            onChanged()
            await load()
        }
    }

    /// The steps already done are skipped.
    func retry() async {
        await run()
    }

    func stop() {
        runner.stop()
    }

    var failedStep: MachinePlanStep? {
        flow?.plan.first { runner.status(of: $0) == .failed }
    }

    /// Once a step changed the configuration the answers that made it are
    /// spent (a new workspace now exists by that name); only Retry is left.
    var canEditAnswers: Bool {
        guard let flow, !isRunning else { return false }
        return !flow.plan.contains { runner.status(of: $0) == .done }
    }

    func editAnswers() {
        guard canEditAnswers else { return }
        runner.reset()
        flow?.editAnswers()
    }

    static func label(_ action: WorkspaceAction) -> String {
        switch action {
        case .new: return "Adding a workspace…"
        case .edit: return "Changing a workspace…"
        case .forget: return "Forgetting a workspace…"
        case .destroy: return "Destroying a workspace…"
        }
    }

    /// Everything that reads the configuration reads it again: the sidebar,
    /// Settings → Machines, readiness and the cached workspace list.
    static func reloadEverything() {
        DataCache.shared.invalidate(.workspaces)
        MachinesStore.shared.requestLoad()
        MachineReadinessStore.shared.requestCheck()
        AppModel.shared?.reloadConfiguration()
    }
}
