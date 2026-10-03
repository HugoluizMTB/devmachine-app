import Foundation

public enum PackageStatus: Equatable, Sendable {
    case applied
    case appliedAsDependency(of: String)
    case pendingInstall
    case pendingRemove
    case available

    public var isInstalled: Bool { self != .available }
    public var isPending: Bool { self == .pendingInstall || self == .pendingRemove }
}

/// Declared comes from the configuration (`installed_on`), applied from the
/// lock. The lock lists `needs` expanded, so a package another one brings
/// in is applied as its dependency, never "pending remove".
public enum PackageStatusCheck {
    public static let accountPackage = "workspace"

    public static func evaluate(
        entries: [PackageEntry], target: PackageTarget, lock: PackagesLock?, workspacesOnMachine: [String] = []
    ) -> [String: PackageStatus] {
        let declared = Set(entries.filter { $0.installedOn.contains(target.installedOnLabel) }.map(\.name))
        var parents: [String: String] = [:]
        let needs = Dictionary(entries.map { ($0.name, $0.needs) }, uniquingKeysWith: { first, _ in first })
        var roots = declared.sorted()
        if case .workspace = target, needs[accountPackage] != nil {
            roots.insert(accountPackage, at: 0)
            parents[accountPackage] = accountPackage
        }
        if case .machine = target {
            let labels = Set(workspacesOnMachine.map { "workspace \($0)" })
            for entry in entries where !labels.isDisjoint(with: entry.installedOn) {
                for need in entry.needs where parents[need] == nil && !declared.contains(need) {
                    parents[need] = entry.name
                }
            }
        }
        var queue = roots
        var included = Set(roots)
        while let next = queue.first {
            queue.removeFirst()
            for need in needs[next] ?? [] where included.insert(need).inserted {
                if parents[need] == nil { parents[need] = next }
                queue.append(need)
            }
        }
        for (name, _) in parents { included.insert(name) }

        var out: [String: PackageStatus] = [:]
        for entry in entries {
            let name = entry.name
            guard let lock else {
                out[name] = declared.contains(name) ? .applied
                    : included.contains(name) ? .appliedAsDependency(of: parents[name] ?? name) : .available
                continue
            }
            let locked = lock.names(for: target).contains(name)
            switch (declared.contains(name), included.contains(name), locked) {
            case (true, _, true): out[name] = .applied
            case (false, true, true): out[name] = .appliedAsDependency(of: parents[name] ?? name)
            case (_, true, false): out[name] = .pendingInstall
            case (false, false, true): out[name] = .pendingRemove
            default: out[name] = .available
            }
        }
        if let lock {
            let known = Set(entries.map(\.name))
            for name in lock.names(for: target) where !known.contains(name) { out[name] = .pendingRemove }
        }
        return out
    }
}
