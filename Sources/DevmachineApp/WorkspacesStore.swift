import Foundation
import DevmachineCore

/// What one read of the workspaces found: the CLI's list, and the lock that
/// says what the last sync applied.
struct WorkspacesSnapshot: Equatable, Sendable {
    var workspaces: [WorkspaceSummary]
    var lock: PackagesLock?

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
        return WorkspacesSnapshot(workspaces: try cli.workspaceSummaries(), lock: lock)
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
    private let onChanged: @MainActor () -> Void

    init(
        machines: MachinesStore = .shared,
        runner: MachineStepRunner = MachineStepRunner(),
        read: @escaping @Sendable () async throws -> WorkspacesSnapshot = {
            try await Task.detached { try WorkspacesReader.read(cli: DevmachineCLI.resolve()) }.value
        },
        loadMachines: Bool = true,
        onChanged: @escaping @MainActor () -> Void = { WorkspacesStore.reloadEverything() }
    ) {
        self.machines = machines
        self.runner = runner
        self.read = read
        self.loadMachines = loadMachines
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

    var packageCards: [MachinePackageCard] {
        WorkspacePackageCatalog.cards(
            from: (machines.snapshot?.packages ?? []).map(\.info), keeping: flow?.current?.packages ?? [])
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
            packages: WorkspacePackageCatalog.preselected(from: packageCards)))
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
