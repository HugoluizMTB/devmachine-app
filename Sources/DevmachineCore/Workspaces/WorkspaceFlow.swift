import Foundation

/// One workspace as `workspaces list --format json` gives it, settings as text.
public struct WorkspaceSummary: Equatable, Sendable, Identifiable {
    public let name: String
    public let machine: String
    public let user: String
    public let packages: [String]
    public let settings: [String: String]
    /// Its own login answers, `machine` or `own` (CLI 0.7.29+).
    public let credentials: [String: String]

    public var id: String { name }

    public init(
        name: String, machine: String, user: String, packages: [String], settings: [String: String] = [:],
        credentials: [String: String] = [:]
    ) {
        self.name = name
        self.machine = machine
        self.user = user
        self.packages = packages
        self.settings = settings
        self.credentials = credentials
    }
}

/// A machine a new workspace can go on: never this Mac's own `self` machine.
public struct WorkspaceMachineChoice: Equatable, Sendable, Identifiable {
    public let name: String
    public let adminUser: String

    public var id: String { name }

    public init(name: String, adminUser: String) {
        self.name = name
        self.adminUser = adminUser
    }
}

public enum WorkspaceAction: Equatable, Sendable {
    case new
    case edit(String)
    case forget(String)
    case destroy(String)
}

public enum WorkspaceFlowStage: Equatable, Sendable {
    case form, review, run
}

public struct WorkspaceDraft: Equatable, Sendable {
    public var name = ""
    public var machine = ""
    public var packages: [String] = []
    public var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    public init() {}
}

/// The Workspaces page's flows. New and Edit go form, review of the exact
/// commands, run; Forget and Destroy show their one command on their own
/// screen and run from there (Destroy only once the name is typed again).
/// A run has no way back except to its answers.
public struct WorkspaceFlow: Equatable, Sendable {
    public let action: WorkspaceAction
    public private(set) var stage: WorkspaceFlowStage = .form
    public let machines: [WorkspaceMachineChoice]
    public let existingWorkspaces: [String]
    /// The workspace Edit, Forget and Destroy act on.
    public let current: WorkspaceSummary?
    public var draft = WorkspaceDraft()
    /// Edit: the packages chosen, and the settings as they will be.
    public var packages: [String] = []
    public var settings: [WorkspaceSetting] = []
    /// Edit: the workspace's own login answers as they will be.
    public var sharing: [String: String] = [:]
    /// New and Edit end with `sync`, unless the person turns it off.
    public var sync = true
    /// Destroy: the name typed again.
    public var typedName = ""
    public var keepDNS = false

    private init(action: WorkspaceAction, machines: [WorkspaceMachineChoice], existing: [String], current: WorkspaceSummary?) {
        self.action = action
        self.machines = machines
        self.existingWorkspaces = existing
        self.current = current
    }

    public static func new(
        machines: [WorkspaceMachineChoice], existingWorkspaces: [String], packages: [String]
    ) -> WorkspaceFlow {
        var flow = WorkspaceFlow(action: .new, machines: machines, existing: existingWorkspaces, current: nil)
        flow.draft.machine = machines.first?.name ?? ""
        flow.draft.packages = packages
        return flow
    }

    public static func edit(_ workspace: WorkspaceSummary) -> WorkspaceFlow {
        var flow = WorkspaceFlow(action: .edit(workspace.name), machines: [], existing: [], current: workspace)
        flow.packages = workspace.packages
        flow.sharing = workspace.credentials
        flow.settings = workspace.settings.keys.sorted().map {
            WorkspaceSetting(key: $0, value: workspace.settings[$0] ?? "")
        }
        return flow
    }

    public static func forget(_ workspace: WorkspaceSummary) -> WorkspaceFlow {
        WorkspaceFlow(action: .forget(workspace.name), machines: [], existing: [], current: workspace)
    }

    public static func destroy(_ workspace: WorkspaceSummary) -> WorkspaceFlow {
        WorkspaceFlow(action: .destroy(workspace.name), machines: [], existing: [], current: workspace)
    }

    public var name: String { current?.name ?? draft.trimmedName }

    /// The machine the workspace lives on, and where `sync` runs.
    public var machine: String { current?.machine ?? draft.machine }

    public var nameProblem: String? {
        guard action == .new else { return nil }
        let admin = machines.first { $0.name == draft.machine }?.adminUser
        return WorkspaceName.problem(draft.name, adminUser: admin, existing: existingWorkspaces)
    }

    public var settingProblems: [String] {
        settings.compactMap { $0.problem(packages: packages) }
    }

    public var changes: WorkspaceChanges {
        guard let current else { return WorkspaceChanges() }
        return WorkspaceChanges.between(
            packages: current.packages, settings: current.settings, chosenPackages: packages, chosenSettings: settings,
            sharing: current.credentials, chosenSharing: sharing)
    }

    public var canAdvance: Bool {
        switch stage {
        case .run: return false
        case .review: return true
        case .form:
            switch action {
            case .new: return nameProblem == nil && machines.contains { $0.name == draft.machine }
            case .edit: return settingProblems.isEmpty && !changes.isEmpty
            case .forget: return true
            case let .destroy(name): return typedName == name
            }
        }
    }

    public var hasReview: Bool {
        switch action {
        case .new, .edit: return true
        case .forget, .destroy: return false
        }
    }

    public var canGoBack: Bool { stage == .review }

    public mutating func next() {
        guard canAdvance else { return }
        stage = stage == .form && hasReview ? .review : .run
    }

    public mutating func back() {
        guard canGoBack else { return }
        stage = .form
    }

    /// A failed or stopped run goes back to its answers, every one kept.
    public mutating func editAnswers() {
        guard stage == .run else { return }
        stage = .form
    }

    public var plan: [MachinePlanStep] {
        switch action {
        case .new:
            return WorkspacePlan.newSteps(name: draft.trimmedName, machine: draft.machine, packages: draft.packages, sync: sync)
        case let .edit(name):
            return WorkspacePlan.editSteps(name: name, machine: machine, changes: changes, sync: sync)
        case let .forget(name):
            return WorkspacePlan.forgetSteps(name: name)
        case let .destroy(name):
            return WorkspacePlan.destroySteps(name: name, keepDNS: keepDNS)
        }
    }

    public func isSelected(_ package: String) -> Bool {
        package == WorkspacePackageCatalog.account || chosen.contains(package)
    }

    /// The account package is always there; it is never toggled.
    public mutating func togglePackage(_ package: String) {
        guard package != WorkspacePackageCatalog.account else { return }
        var list = chosen
        if let index = list.firstIndex(of: package) {
            list.remove(at: index)
        } else {
            list.append(package)
        }
        if action == .new { draft.packages = list } else { packages = list }
    }

    /// A declared variable's value as set, empty when it is left at its default.
    public func settingValue(_ key: String) -> String {
        settings.first { $0.key == key }?.value ?? ""
    }

    /// An empty value takes the setting out, back to the package's default.
    public mutating func setSetting(_ key: String, _ value: String) {
        let index = settings.firstIndex { $0.key == key }
        switch (index, value.isEmpty) {
        case let (index?, true): settings.remove(at: index)
        case let (index?, false): settings[index].value = value
        case (nil, false): settings.append(WorkspaceSetting(key: key, value: value))
        case (nil, true): break
        }
    }

    /// `machine`, `own`, or nil to follow what the configuration says.
    public mutating func setSharing(_ login: String, _ value: String?) {
        sharing[login] = value
    }

    public mutating func addSetting() {
        settings.append(WorkspaceSetting(key: "", value: ""))
    }

    public mutating func removeSetting(at index: Int) {
        guard settings.indices.contains(index) else { return }
        settings.remove(at: index)
    }

    private var chosen: [String] { action == .new ? draft.packages : packages }
}
