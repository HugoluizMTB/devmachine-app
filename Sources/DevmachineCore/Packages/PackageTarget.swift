import Foundation

/// Where a package goes: a machine, or a workspace on one. A workspace's
/// packages are applied by syncing the machine it lives on.
public enum PackageTarget: Hashable, Sendable {
    case machine(String, isSelf: Bool)
    case workspace(String, machine: String)

    public var name: String {
        switch self {
        case let .machine(name, _), let .workspace(name, _): return name
        }
    }

    public var syncMachine: String {
        switch self {
        case let .machine(name, _): return name
        case let .workspace(_, machine): return machine
        }
    }

    public var scope: String {
        switch self {
        case .machine: return "machine"
        case .workspace: return "workspace"
        }
    }

    public var installedOnLabel: String { "\(scope) \(name)" }

    public var flag: [String] { ["--\(scope)", name] }

    public var title: String {
        switch self {
        case let .machine(name, _): return name
        case let .workspace(name, machine): return "\(name) on \(machine)"
        }
    }
}
