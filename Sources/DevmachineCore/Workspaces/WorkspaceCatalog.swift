import Foundation

/// A value from `workspaces list --format json`'s `settings`, any JSON. It
/// is shown and sent back as text the CLI reads as YAML, which every JSON
/// value already is.
public indirect enum SettingValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([SettingValue])
    case object([String: SettingValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SettingValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SettingValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .object(values): try container.encode(values)
        case .null: try container.encodeNil()
        }
    }

    /// A string as it is; anything else as compact JSON.
    public var text: String {
        if case let .string(value) = self { return value }
        return json
    }

    private var json: String {
        switch self {
        case let .string(value):
            let data = (try? JSONEncoder().encode(value)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return "null"
        case let .array(values): return "[" + values.map(\.json).joined(separator: ",") + "]"
        case let .object(values):
            let pairs = values.keys.sorted().map { SettingValue.string($0).json + ":" + (values[$0]?.json ?? "null") }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }
}

/// The package cards of a workspace: workspace packages that run on Linux,
/// grouped under their catalog heading.
public enum WorkspacePackageCatalog {
    /// Every workspace gets it, listed or not: it creates the Linux account
    /// (the CLI's `packages.AccountPackage`), and it cannot be taken off.
    public static let account = "workspace"
    /// What `devmachine setup` writes into `defaults.workspace`
    /// (`config.DefaultWorkspacePackages`). The CLI has no command that
    /// prints the configured defaults, so a changed list is not seen here.
    public static let cliDefaults = ["dev", "zsh", "mise"]
    public static let categoryOrder = ["Foundation", "Coding agents", "Developer tools"]
    public static let otherCategory = "Other"

    public struct Group: Equatable, Sendable {
        public let title: String
        public let cards: [MachinePackageCard]
    }

    /// `keeping` are packages the workspace already has: one the list does
    /// not know (renamed, or from a folder that is gone) still gets a card,
    /// so it can be taken off.
    ///
    /// `hiding` are coding agents' packages that are not offered (their
    /// harness is off): they leave, with anything that needs them, unless
    /// the workspace already has them.
    public static func cards(
        from packages: [PackageInfo], keeping: [String] = [], hiding: Set<String> = [],
        defaults: [String] = cliDefaults, platform: String = MachinePackageCatalog.linux
    ) -> [MachinePackageCard] {
        let hidden = hiding.subtracting(keeping)
        var cards = packages
            .filter { $0.scope == "workspace" && MachinePackageCatalog.runs($0, on: platform) }
            .filter { !hidden.contains($0.name) && hidden.isDisjoint(with: $0.needs) }
            .map { package in
                let summary = package.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                return MachinePackageCard(
                    name: package.name, summary: summary.isEmpty ? "No description." : summary,
                    isRecommended: defaults.contains(package.name), isYours: package.source == "local",
                    locked: package.name == account, category: package.category)
            }
        for name in keeping where !cards.contains(where: { $0.name == name }) {
            cards.append(MachinePackageCard(
                name: name, summary: "Not in this configuration's package list.", isRecommended: false,
                isYours: false, locked: false))
        }
        return cards.sorted { lhs, rhs in
            let left = rank(lhs.category), right = rank(rhs.category)
            if left != right { return left < right }
            if lhs.isLocked != rhs.isLocked { return lhs.isLocked }
            return lhs.name < rhs.name
        }
    }

    public static func groups(_ cards: [MachinePackageCard]) -> [Group] {
        var titles: [String] = []
        for card in cards where !titles.contains(title(card.category)) {
            titles.append(title(card.category))
        }
        return titles.map { title in Group(title: title, cards: cards.filter { Self.title($0.category) == title }) }
    }

    /// The defaults (`defaults.workspace`, or the setup's own on an older
    /// CLI) that are offered as cards.
    public static func preselected(from cards: [MachinePackageCard], defaults: [String] = cliDefaults) -> [String] {
        defaults.filter { name in cards.contains { $0.name == name } }
    }

    private static func title(_ category: String) -> String {
        category.isEmpty ? otherCategory : category
    }

    private static func rank(_ category: String) -> Int {
        if let index = categoryOrder.firstIndex(of: category) { return index }
        return category.isEmpty ? categoryOrder.count + 1 : categoryOrder.count
    }
}

/// Identifying a harness and activating it are different. Every known
/// harness is identified; only one whose package (the workspace package
/// that installs it) is in the pinned release can be turned on, and only
/// the ones turned on are offered as a new workspace's coding agents.
public struct CodingAgentPackages: Equatable, Sendable {
    public let offered: [String]
    /// Every other harness's package.
    public let hidden: Set<String>

    /// `available` is the release's package names; nil (not read yet)
    /// trusts the package each harness declares.
    public static func activatable(harnesses: [(HarnessID, String?)], available: Set<String>?) -> [HarnessID] {
        harnesses.compactMap { id, package in
            guard let package, available?.contains(package) ?? true else { return nil }
            return id
        }
    }

    public static func choose(
        harnesses: [(HarnessID, String?)], enabled: [HarnessID], available: Set<String>?
    ) -> CodingAgentPackages {
        let on = Set(activatable(harnesses: harnesses, available: available)).intersection(enabled)
        let packages = harnesses.compactMap { id, package in package.map { (id, $0) } }
        return CodingAgentPackages(
            offered: packages.filter { on.contains($0.0) }.map(\.1),
            hidden: Set(packages.filter { !on.contains($0.0) }.map(\.1)))
    }
}

/// Whether the last sync applied what the configuration asks of a workspace,
/// read from `packages.lock` without logging in.
public enum WorkspaceSyncState: Equatable, Sendable {
    case applied
    /// These declared packages are not in the lock yet.
    case pending([String])
    /// The lock does not name the workspace: no sync has created it.
    case neverSynced
    /// No lock could be read.
    case unknown
}

public enum WorkspaceSync {
    /// A package taken off is not caught: the lock also lists what the
    /// declared ones pull in, so an extra entry proves nothing.
    public static func state(workspace: String, packages: [String], lock: PackagesLock?) -> WorkspaceSyncState {
        guard let lock else { return .unknown }
        guard let applied = lock.workspaces[workspace] else { return .neverSynced }
        let names = Set(applied.map(\.name))
        let missing = packages.filter { !names.contains($0) }
        return missing.isEmpty ? .applied : .pending(missing)
    }
}
