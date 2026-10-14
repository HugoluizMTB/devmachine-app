import Foundation

/// Why a package cannot be ticked for a target, said in the row.
public enum PackageBlock: Equatable, Sendable {
    case noRecipe
    case wrongScope(String)
    /// The package runs only on these systems, and the machine runs another.
    case otherSystem(runsOn: [String])
    case essentials
    case account
    case dependency(of: String)

    public var message: String {
        switch self {
        case .noRecipe: return "No package provides it any more."
        case let .wrongScope(scope): return "Goes on a \(scope)."
        case .otherSystem: return label + "."
        case .essentials: return "Every machine keeps essentials."
        case .account: return "Creates the workspace's account."
        case let .dependency(parent): return "Comes with \(parent)."
        }
    }

    /// The few words a row shows beside the package: "Linux only".
    public var label: String {
        guard case let .otherSystem(platforms) = self else { return message }
        let names = platforms.map(PackageAvailability.title(platform:))
        return names.count == 1 ? "\(names[0]) only" : "Runs on " + names.joined(separator: ", ")
    }
}

/// Whether a package's `platforms` let it go on the system a machine runs.
public enum PackageSystemFit: Equatable, Sendable {
    case fits
    /// It cannot be ticked or installed there.
    case blocked(String)
    /// Installed there already: it cannot be installed again, but it comes off.
    case removableOnly(String)

    public var label: String? {
        switch self {
        case .fits: return nil
        case let .blocked(label), let .removableOnly(label): return label
        }
    }

    public var canTick: Bool {
        if case .blocked = self { return false }
        return true
    }
}

public enum PackageAvailability {
    /// `platform` is the system of the machine the target is on, as the CLI
    /// last read it. This Mac is `macos` without it; any other machine the
    /// CLI never read is unknown and blocks nothing, since the CLI's own sync
    /// refuses a package for another system once it reads the machine.
    public static func block(
        entry: PackageEntry, status: PackageStatus, target: PackageTarget, platform: String? = nil
    ) -> PackageBlock? {
        guard !entry.scope.isEmpty else { return .noRecipe }
        guard entry.scope == target.scope else { return .wrongScope(entry.scope) }
        if systemFit(platforms: entry.platforms, system: system(of: target, reported: platform), installed: false)
            != .fits {
            return .otherSystem(runsOn: entry.platforms)
        }
        if case .workspace = target, entry.name == PackageStatusCheck.accountPackage { return .account }
        if entry.name == "essentials", status.isInstalled, status != .pendingRemove { return .essentials }
        if case let .appliedAsDependency(parent) = status { return .dependency(of: parent) }
        return nil
    }

    public static func system(of target: PackageTarget, reported: String?) -> String? {
        if let reported { return reported }
        if case .machine(_, isSelf: true) = target { return "macos" }
        return nil
    }

    /// Empty `platforms` is any system, and an unknown system takes anything.
    public static func systemFit(platforms: [String], system: String?, installed: Bool) -> PackageSystemFit {
        guard let system, !platforms.isEmpty, !platforms.contains(system) else { return .fits }
        let label = PackageBlock.otherSystem(runsOn: platforms).label
        return installed ? .removableOnly(label) : .blocked(label)
    }

    /// One answer for several places at once, as the row does for the picked
    /// machine and workspace: it fits when it fits any of them.
    public static func systemFit(
        platforms: [String], on places: [(system: String?, installed: Bool)]
    ) -> PackageSystemFit {
        let fits = places.map { systemFit(platforms: platforms, system: $0.system, installed: $0.installed) }
        if fits.isEmpty || fits.contains(.fits) { return .fits }
        return fits.first { if case .removableOnly = $0 { return true } else { return false } } ?? fits[0]
    }

    static func title(platform: String) -> String {
        switch platform {
        case "linux": return "Linux"
        case "macos": return "macOS"
        default: return platform
        }
    }
}
