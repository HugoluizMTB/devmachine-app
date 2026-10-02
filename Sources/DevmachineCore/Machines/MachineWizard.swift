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
public struct MachineWizard: Equatable, Sendable {
    public private(set) var stage: MachineWizardStage = .kind
    public var draft = MachineDraft()
    public let existingMachines: [String]
    public let limaFound: Bool

    public init(existingMachines: [String], limaFound: Bool) {
        self.existingMachines = existingMachines
        self.limaFound = limaFound
    }

    public var problems: [MachineDraftProblem] { draft.problems(existingMachines: existingMachines) }

    public func canChoose(_ kind: MachineKind) -> Bool {
        kind == .server || limaFound
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
    /// rebuilt around fresh context. Never into a run: only `next` starts one.
    public mutating func restore(_ stage: MachineWizardStage) {
        guard stage != .run else { return }
        self.stage = stage
    }

    public var plan: [MachinePlanStep] { MachinePlan.steps(for: draft) }

    public func isSelected(_ package: String) -> Bool {
        package == MachinePackageCatalog.essentials ? draft.essentials : draft.packages.contains(package)
    }

    /// `essentials` is what `machines add` starts a machine with unless
    /// `--no-essentials`, so it is that flag, never a `packages add`.
    public mutating func togglePackage(_ package: String) {
        if package == MachinePackageCatalog.essentials {
            draft.essentials.toggle()
        } else if let index = draft.packages.firstIndex(of: package) {
            draft.packages.remove(at: index)
        } else {
            draft.packages.append(package)
        }
    }
}

/// One row of `devmachine packages list --format json`, as Core needs it.
public struct PackageInfo: Equatable, Sendable {
    public let name: String
    public let scope: String
    public let summary: String
    public let source: String

    public init(name: String, scope: String, summary: String, source: String) {
        self.name = name
        self.scope = scope
        self.summary = summary
        self.source = source
    }
}

public struct MachinePackageCard: Equatable, Sendable, Identifiable {
    public let name: String
    public let summary: String
    /// What `machines add` starts a machine with.
    public let isRecommended: Bool
    /// A package from the person's own folder, not the release.
    public let isYours: Bool

    public var id: String { name }

    public init(name: String, summary: String, isRecommended: Bool, isYours: Bool) {
        self.name = name
        self.summary = summary
        self.isRecommended = isRecommended
        self.isYours = isYours
    }
}

public enum MachinePackageCatalog {
    public static let essentials = "essentials"

    /// Machine packages only (a workspace package goes on a workspace), with
    /// essentials first and the rest by name.
    public static func cards(from packages: [PackageInfo]) -> [MachinePackageCard] {
        packages
            .filter { $0.scope == "machine" }
            .map { package in
                let summary = package.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                return MachinePackageCard(
                    name: package.name,
                    summary: summary.isEmpty ? "No description." : summary,
                    isRecommended: package.name == essentials,
                    isYours: package.source == "local")
            }
            .sorted { lhs, rhs in
                if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
                return lhs.name < rhs.name
            }
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
/// so it looks where Homebrew installs it.
public enum LimaTool {
    public static let installCommand = "brew install lima"
    public static let paths = ["/opt/homebrew/bin/limactl", "/usr/local/bin/limactl"]

    public static func find(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        paths.first(where: exists)
    }
}
