import Foundation

public enum LRUEviction {
    public static func keysToEvict<Key: Hashable>(detachedAt: [Key: Date], cap: Int) -> [Key] {
        let limit = max(0, cap)
        guard detachedAt.count > limit else { return [] }
        let oldestFirst = detachedAt.sorted { $0.value < $1.value }
        return oldestFirst.prefix(detachedAt.count - limit).map(\.key)
    }
}
