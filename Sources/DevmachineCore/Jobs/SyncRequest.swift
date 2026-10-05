import Foundation

/// A sync some part of the app asks for. Two asks for the same machine
/// become one: the tags join, and a full sync wins. No tags means full.
public struct SyncRequest: Equatable, Sendable {
    public let machine: String
    public let tags: [String]
    public let full: Bool
    public let reasons: [String]

    public init(machine: String, tags: [String] = [], full: Bool = false, reasons: [String] = []) {
        self.machine = machine
        self.tags = Self.unique(tags)
        self.full = full || tags.isEmpty
        self.reasons = Self.unique(reasons)
    }

    public func merging(_ other: SyncRequest) -> SyncRequest {
        guard other.machine == machine else { return self }
        return SyncRequest(
            machine: machine, tags: tags + other.tags, full: full || other.full, reasons: reasons + other.reasons)
    }

    public func arguments(full runsFull: Bool) -> [String] {
        var arguments = ["sync", "--machine", machine]
        if !runsFull, !tags.isEmpty { arguments += ["--tags", tags.joined(separator: ",")] }
        return arguments + ["--yes"]
    }

    /// A tagged sync never records a removal, and a CLI before 0.7.24 wrote
    /// the whole plan into the lock on a tagged one.
    public func startsFull(cliVersion: SemanticVersion?) -> Bool {
        full || !MachinePrepare.canPrepareInApp(cliVersion: cliVersion)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
