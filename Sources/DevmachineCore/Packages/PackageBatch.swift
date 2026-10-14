import Foundation

public enum PackageAction: String, Equatable, Sendable {
    case install, remove
}

/// A package left out of a batch for one target, and why.
public struct PackageSkip: Equatable, Sendable {
    public let package: String
    public let target: PackageTarget
    public let reason: String

    public init(package: String, target: PackageTarget, reason: String) {
        self.package = package
        self.target = target
        self.reason = reason
    }
}

/// One or more packages, installed on or removed from one or more machines
/// and workspaces. A package that does not fit a target, or already is what
/// the action asks, is skipped for that target and said why.
public struct PackageBatch: Equatable, Sendable {
    public let edits: [(target: PackageTarget, changes: PackageChanges)]
    public let skips: [PackageSkip]

    public static func == (lhs: PackageBatch, rhs: PackageBatch) -> Bool {
        lhs.skips == rhs.skips && lhs.edits.map(\.target) == rhs.edits.map(\.target)
            && lhs.edits.map(\.changes) == rhs.edits.map(\.changes)
    }

    public init(edits: [(target: PackageTarget, changes: PackageChanges)], skips: [PackageSkip] = []) {
        self.edits = edits
        self.skips = skips
    }

    public var isEmpty: Bool { edits.isEmpty }

    public static func plan(
        packages: [String], targets: [PackageTarget], action: PackageAction,
        entries: [PackageEntry], statuses: (PackageTarget) -> [String: PackageStatus],
        platform: (PackageTarget) -> String? = { _ in nil }
    ) -> PackageBatch {
        let byName = Dictionary(entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var edits: [(PackageTarget, PackageChanges)] = []
        var skips: [PackageSkip] = []
        for target in targets {
            let current = statuses(target)
            var names: [String] = []
            for package in packages.sorted() {
                guard let entry = byName[package] else { continue }
                let status = current[package] ?? .available
                if let reason = skipReason(
                    entry: entry, status: status, target: target, platform: platform(target), action: action) {
                    skips.append(PackageSkip(package: package, target: target, reason: reason))
                } else {
                    names.append(package)
                }
            }
            guard !names.isEmpty else { continue }
            let changes = action == .install
                ? PackageChanges(adds: names, removes: [])
                : PackageChanges(adds: [], removes: names)
            edits.append((target, changes))
        }
        return PackageBatch(edits: edits, skips: skips)
    }

    private static func skipReason(
        entry: PackageEntry, status: PackageStatus, target: PackageTarget, platform: String?, action: PackageAction
    ) -> String? {
        switch PackageAvailability.block(entry: entry, status: status, target: target, platform: platform) {
        case .otherSystem where action == .remove && status.isInstalled: break
        case let block?: return block.message
        case nil: break
        }
        switch (action, status) {
        case (.install, .applied), (.install, .pendingInstall): return "Already there."
        case (.remove, .available): return "Not there."
        case (.remove, .pendingRemove): return "Already being removed."
        default: return nil
        }
    }

    /// The targets a package can go on at all, before what each one has. A
    /// machine of another system takes it only to remove one already there.
    public static func fits(
        _ entry: PackageEntry, on target: PackageTarget, platform: String? = nil, status: PackageStatus = .available
    ) -> Bool {
        switch PackageAvailability.block(entry: entry, status: .available, target: target, platform: platform) {
        case .noRecipe, .wrongScope, .account: return false
        case .otherSystem: return status.isInstalled
        default: return true
        }
    }
}
