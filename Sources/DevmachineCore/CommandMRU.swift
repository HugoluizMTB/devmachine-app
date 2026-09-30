import Foundation

/// The palette commands run most recently, newest first, and the ranking
/// bonus each one earns for it.
public struct CommandMRU: Equatable, Sendable {
    public static let defaultCapacity = 8
    public static let topBoost = 240

    public let ids: [String]
    public let capacity: Int

    public init(ids: [String], capacity: Int = CommandMRU.defaultCapacity) {
        self.capacity = max(capacity, 1)
        self.ids = Array(ids.prefix(self.capacity))
    }

    public func recording(_ id: String) -> CommandMRU {
        CommandMRU(ids: [id] + ids.filter { $0 != id }, capacity: capacity)
    }

    public func boost(for id: String) -> Int {
        guard let rank = ids.firstIndex(of: id) else { return 0 }
        return Self.topBoost * (capacity - rank) / capacity
    }
}
