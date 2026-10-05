import Foundation

/// The rows ticked on one target. A tick on an installed package removes
/// it; on any other it adds it.
public struct PackageSelection: Equatable, Sendable {
    public private(set) var names: Set<String> = []

    public init() {}

    public mutating func toggle(_ name: String) {
        if names.remove(name) == nil { names.insert(name) }
    }

    public mutating func clear() { names = [] }

    public func changes(statuses: [String: PackageStatus]) -> PackageChanges {
        var adds: [String] = []
        var removes: [String] = []
        for name in names.sorted() {
            switch statuses[name] ?? .available {
            case .applied, .pendingInstall, .appliedAsDependency: removes.append(name)
            case .available, .pendingRemove: adds.append(name)
            }
        }
        return PackageChanges(adds: adds, removes: removes)
    }
}

public struct PackageChanges: Equatable, Sendable {
    public let adds: [String]
    public let removes: [String]

    public init(adds: [String], removes: [String]) {
        self.adds = adds
        self.removes = removes
    }

    public var isEmpty: Bool { adds.isEmpty && removes.isEmpty }

    public func commands(target: PackageTarget) -> [[String]] {
        adds.map { ["packages", "add", $0] + target.flag + ["--yes"] }
            + removes.map { ["packages", "rm", $0] + target.flag + ["--yes"] }
    }

    /// A tagged sync never records a removal, so any removal asks for a full one.
    public func syncRequest(target: PackageTarget) -> SyncRequest? {
        guard !isEmpty else { return nil }
        return SyncRequest(machine: target.syncMachine, tags: adds, full: !removes.isEmpty, reasons: ["Packages"])
    }
}

public enum PackagePending {
    public static func syncRequest(statuses: [String: PackageStatus], target: PackageTarget) -> SyncRequest? {
        let installs = statuses.filter { $0.value == .pendingInstall }.keys.sorted()
        let removes = statuses.contains { $0.value == .pendingRemove }
        guard !installs.isEmpty || removes else { return nil }
        return SyncRequest(machine: target.syncMachine, tags: installs, full: removes, reasons: ["Packages"])
    }
}
