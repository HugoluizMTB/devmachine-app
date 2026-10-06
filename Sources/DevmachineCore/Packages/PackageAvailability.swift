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
        let names = platforms.map { MachinePlatform(rawValue: $0)?.title ?? $0 }
        return names.joined(separator: " or ") + " only"
    }
}

public enum PackageAvailability {
    public static func block(
        entry: PackageEntry, status: PackageStatus, target: PackageTarget, platforms: MachinePlatforms = .legacy
    ) -> PackageBlock? {
        guard !entry.scope.isEmpty else { return .noRecipe }
        guard entry.scope == target.scope else { return .wrongScope(entry.scope) }
        if let block = systemBlock(entry, on: platforms.platform(of: target)) { return block }
        if case .workspace = target, entry.name == PackageStatusCheck.accountPackage { return .account }
        if entry.name == "essentials", status.isInstalled, status != .pendingRemove { return .essentials }
        if case let .appliedAsDependency(parent) = status { return .dependency(of: parent) }
        return nil
    }

    /// Empty `platforms` is any system, and an unknown machine takes anything.
    public static func systemBlock(_ entry: PackageEntry, on platform: MachinePlatform?) -> PackageBlock? {
        guard let platform, !entry.platforms.isEmpty, !entry.platforms.contains(platform.rawValue) else { return nil }
        return .otherSystem(runsOn: entry.platforms)
    }
}
