import Foundation

/// Why a package cannot be ticked for a target, said in the row.
public enum PackageBlock: Equatable, Sendable {
    case noRecipe
    case wrongScope(String)
    case macOnly
    case serverOnly
    case essentials
    case account
    case dependency(of: String)

    public var message: String {
        switch self {
        case .noRecipe: return "No package provides it any more."
        case let .wrongScope(scope): return "Goes on a \(scope)."
        case .macOnly: return "Only for a Mac."
        case .serverOnly: return "Only for a Linux machine."
        case .essentials: return "Every machine keeps essentials."
        case .account: return "Creates the workspace's account."
        case let .dependency(parent): return "Comes with \(parent)."
        }
    }
}

public enum PackageAvailability {
    /// `platform` is the system of the machine the target is on, as the CLI
    /// last read it. Without it a machine is guessed from whether it is this
    /// Mac, and a workspace is not checked.
    public static func block(
        entry: PackageEntry, status: PackageStatus, target: PackageTarget, platform: String? = nil
    ) -> PackageBlock? {
        guard !entry.scope.isEmpty else { return .noRecipe }
        guard entry.scope == target.scope else { return .wrongScope(entry.scope) }
        if !entry.platforms.isEmpty, let system = platform ?? guessedPlatform(target),
           !entry.platforms.contains(system) {
            return system == "macos" ? .serverOnly : .macOnly
        }
        if case .workspace = target, entry.name == PackageStatusCheck.accountPackage { return .account }
        if entry.name == "essentials", status.isInstalled, status != .pendingRemove { return .essentials }
        if case let .appliedAsDependency(parent) = status { return .dependency(of: parent) }
        return nil
    }

    private static func guessedPlatform(_ target: PackageTarget) -> String? {
        guard case let .machine(_, isSelf) = target else { return nil }
        return isSelf ? "macos" : "linux"
    }
}
