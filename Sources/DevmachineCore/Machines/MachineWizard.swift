import Foundation

public enum MachineWizardStage: Int, CaseIterable, Equatable, Sendable {
    case kind, details, packages, review, run

    public var title: String {
        switch self {
        case .kind: return "Kind"
        case .details: return "Details"
        case .packages: return "Packages"
        case .review: return "Review"
        case .run: return "Create"
        }
    }
}

/// The Add machine wizard's state: which step is on screen and every answer
/// so far. Back keeps the answers; a run that started has no way back.
/// The first-run setup is this same wizard with `firstRun`: it always syncs,
/// always adds the package this app reads, and installs the skills.
public struct MachineWizard: Equatable, Sendable {
    public private(set) var stage: MachineWizardStage = .kind
    public var draft = MachineDraft()
    public let existingMachines: [String]
    /// Every workspace in the configuration: a new one cannot take a name.
    public let existingWorkspaces: [String]
    public let limaFound: Bool
    /// The CLI takes every answer as a flag (`MachineUnattendedAdd`): the
    /// whole run happens without a terminal.
    public let unattended: Bool
    public let firstRun: Bool
    /// What this Mac can give a Lima machine, on a CLI that takes the size
    /// (`LocalMachineSizing`); nil keeps the CLI's default size.
    public let sizeLimits: LocalMachineSizeLimits?

    public init(
        existingMachines: [String], existingWorkspaces: [String] = [], limaFound: Bool, unattended: Bool = false,
        firstRun: Bool = false, sizeLimits: LocalMachineSizeLimits? = nil
    ) {
        self.sizeLimits = unattended ? sizeLimits : nil
        self.existingMachines = existingMachines
        self.existingWorkspaces = existingWorkspaces
        self.limaFound = limaFound
        self.unattended = unattended
        self.firstRun = firstRun
    }

    /// The first run makes a workspace unless the person skipped it, so the
    /// app opens with one in the sidebar; adding a machine later needs none.
    public var requiresWorkspace: Bool { firstRun && !draft.skipsWorkspace }

    public var problems: [MachineDraftProblem] {
        var problems = draft.problems(
            existingMachines: existingMachines, unattended: unattended, existingWorkspaces: existingWorkspaces)
        if requiresWorkspace, draft.trimmedWorkspace.isEmpty {
            problems.append(.init(field: .workspace, message: "Name your first workspace, like acme."))
        }
        if draft.kind == .localVM, let size = sizeToCreate, let limits = sizeLimits, !limits.contains(size) {
            problems.append(.init(field: .size, message: "Choose a size this Mac can give the machine."))
        }
        return problems
    }

    /// A CLI that takes every answer as a flag runs in the background, where
    /// a missing Lima is installed as the plan's first step.
    public func canChoose(_ kind: MachineKind) -> Bool {
        kind == .server || limaFound || unattended
    }

    public mutating func choose(_ kind: MachineKind) {
        guard canChoose(kind) else { return }
        draft.kind = kind
        stage = .details
    }

    public var canAdvance: Bool {
        switch stage {
        case .kind: return canChoose(draft.kind)
        case .details: return problems.isEmpty
        case .packages, .review: return true
        case .run: return false
        }
    }

    public var canGoBack: Bool { stage != .kind && stage != .run }

    public mutating func next() {
        guard canAdvance, let following = MachineWizardStage(rawValue: stage.rawValue + 1) else { return }
        stage = following
    }

    public mutating func back() {
        guard canGoBack, let previous = MachineWizardStage(rawValue: stage.rawValue - 1) else { return }
        stage = previous
    }

    /// Back to a step the person already reached, after the wizard was
    /// rebuilt around fresh context, but never past a step that now needs
    /// an answer: a CLI that changed may ask for a password or a
    /// fingerprint the older one did not. Never into a run: only `next`
    /// starts one.
    public mutating func restore(_ target: MachineWizardStage) {
        guard target != .run else { return }
        stage = .kind
        guard stage != target, canAdvance else { return }
        stage = .details
        while stage.rawValue < target.rawValue, canAdvance {
            next()
        }
    }

    /// A run that failed or was stopped goes back to its details, every
    /// answer kept, so a wrong address or password can be fixed.
    public mutating func editAnswers() {
        guard stage == .run else { return }
        stage = .details
    }

    /// The size `create-local` is given: none on a CLI without the flags.
    public var sizeToCreate: LocalMachineSize? {
        sizeLimits == nil ? nil : draft.localSize
    }

    public var plan: [MachinePlanStep] {
        var draft = draft
        draft.localSize = sizeToCreate
        if firstRun {
            draft.sync = true
            if draft.skipsWorkspace { draft.workspace = "" }
            if !draft.packages.contains(MachinePackageCatalog.appPackage) {
                draft.packages.append(MachinePackageCatalog.appPackage)
            }
        } else {
            draft.skillAgents = []
        }
        return MachinePlan.steps(for: draft, unattended: unattended, installsLima: !limaFound)
    }

    public var terminalAnswers: [MachinePlan.Answer] {
        MachinePlan.terminalAnswers(for: draft, unattended: unattended)
    }

    public func isSelected(_ package: String) -> Bool {
        package == MachinePackageCatalog.essentials ? draft.essentials : draft.packages.contains(package)
    }

    /// `essentials` is always installed: it holds what every machine and
    /// this app need, so it is never toggled off.
    public mutating func togglePackage(_ package: String) {
        guard package != MachinePackageCatalog.essentials else { return }
        if let index = draft.packages.firstIndex(of: package) {
            draft.packages.remove(at: index)
        } else {
            draft.packages.append(package)
        }
    }

    public mutating func toggleSkillAgent(_ agent: String) {
        if let index = draft.skillAgents.firstIndex(of: agent) {
            draft.skillAgents.remove(at: index)
        } else {
            draft.skillAgents = SkillAgent.ordered(draft.skillAgents + [agent])
        }
    }
}

/// The coding harnesses `devmachine skills add --agent` links the skills
/// for. The skills land in `~/.agents/skills` whatever is chosen, so a
/// harness installed later finds them; `--agent` works for one not
/// installed yet.
public struct SkillAgent: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public static let all = [
        SkillAgent(id: "claude", name: "Claude Code"),
        SkillAgent(id: "codex", name: "Codex"),
        SkillAgent(id: "pi", name: "Pi"),
        SkillAgent(id: "opencode", name: "OpenCode"),
    ]

    /// Known ids only, in the CLI's order, each once.
    public static func ordered(_ ids: [String]) -> [String] {
        all.map(\.id).filter { ids.contains($0) }
    }

    public static func names(_ ids: [String]) -> [String] {
        all.filter { ids.contains($0.id) }.map(\.name)
    }

    /// What `skills add` finds by itself: each harness's own folder in the home folder.
    public static func detected(home: String, isDirectory: (String) -> Bool) -> [String] {
        let folders = ["claude": ".claude", "codex": ".codex", "pi": ".pi", "opencode": ".config/opencode"]
        return all.map(\.id).filter { isDirectory(home + "/" + (folders[$0] ?? $0)) }
    }
}

/// One row of `devmachine packages list --format json`, as Core needs it.
public struct PackageInfo: Equatable, Sendable {
    public let name: String
    public let scope: String
    public let summary: String
    public let source: String
    /// The operating systems it runs on; empty is any (CLI 0.7.27+).
    public let platforms: [String]
    /// The packages it brings in first: for `essentials`, what it is made of.
    public let needs: [String]

    public init(
        name: String, scope: String, summary: String, source: String, platforms: [String] = [], needs: [String] = []
    ) {
        self.name = name
        self.scope = scope
        self.summary = summary
        self.source = source
        self.platforms = platforms
        self.needs = needs
    }
}

public struct MachinePackageCard: Equatable, Sendable, Identifiable {
    public let name: String
    public let summary: String
    /// What `machines add` starts a machine with.
    public let isRecommended: Bool
    /// A package from the person's own folder, not the release.
    public let isYours: Bool
    /// What `essentials` is made of; empty for any other package.
    public let contains: [String]
    /// Always installed, shown checked and never toggled.
    public var isLocked: Bool { name == MachinePackageCatalog.essentials }

    public var id: String { name }

    public init(name: String, summary: String, isRecommended: Bool, isYours: Bool, contains: [String] = []) {
        self.name = name
        self.summary = summary
        self.isRecommended = isRecommended
        self.isYours = isYours
        self.contains = contains
    }
}

public enum MachinePackageCatalog {
    public static let essentials = "essentials"
    /// What this app reads from a machine. Essentials needs it, but the
    /// first run names it too, so the machine's own list says it is there.
    public static let appPackage = "devmachine-app"
    public static let suggestedPackages = ["docker"]

    public static func suggested(from cards: [MachinePackageCard]) -> [String] {
        suggestedPackages.filter { name in cards.contains { $0.name == name } }
    }
    /// A server is always Linux, and so is a Lima machine on this Mac.
    public static let linux = "linux"

    /// Machine packages only (a workspace package goes on a workspace) that
    /// run on `platform`, with essentials first and the rest by name. What
    /// essentials is made of is not offered again on its own.
    public static func cards(from packages: [PackageInfo], platform: String = linux) -> [MachinePackageCard] {
        let included = packages.first { $0.name == essentials }?.needs ?? []
        return packages
            .filter { $0.scope == "machine" && runs($0, on: platform) && !included.contains($0.name) }
            .map { package in
                let summary = package.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                return MachinePackageCard(
                    name: package.name,
                    summary: summary.isEmpty ? "No description." : summary,
                    isRecommended: package.name == essentials,
                    isYours: package.source == "local",
                    contains: package.name == essentials ? package.needs : [])
            }
            .sorted { lhs, rhs in
                if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
                return lhs.name < rhs.name
            }
    }

    /// No platform listed means any: a package written before the field
    /// existed runs wherever it ran before.
    public static func runs(_ package: PackageInfo, on platform: String) -> Bool {
        package.platforms.isEmpty || package.platforms.contains(platform)
    }
}

/// The sidebar's "Add a machine" button, above Local: only once the
/// configuration was read and holds no machine besides this Mac.
public enum AddMachinePrompt {
    public static func shows(remoteMachines: [String]?) -> Bool {
        remoteMachines?.isEmpty ?? false
    }
}

/// `create-local` needs Lima. An app opened from Finder has no shell PATH,
/// so it looks where Homebrew installs it, and in `~/.local/bin`, where the
/// app unpacks Lima's own release (`LimaInstall`).
public enum LimaTool {
    public static let installCommand = "brew install lima"
    public static let paths = ["/opt/homebrew/bin/limactl", "/usr/local/bin/limactl"]

    public static func find(
        home: String = NSHomeDirectory(),
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        (paths + [LimaInstall.limactl(home: home)]).first(where: exists)
    }
}
