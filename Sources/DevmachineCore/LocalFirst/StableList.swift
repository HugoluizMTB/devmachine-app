import Foundation

public struct StableMerge<Element: Identifiable> {
    public let list: [Element]
    public let inserted: [Element.ID]
    public let removed: [Element.ID]
    public let updated: [Element.ID]

    public var changed: Bool { !inserted.isEmpty || !removed.isEmpty || !updated.isEmpty }
}

/// Lays a fresh answer over the list on screen by identity, so a refresh
/// changes only the rows that changed. A reorder alone is not a change: rows
/// that jump with nothing new in them read as flicker.
public enum StableList {
    public static func merge<Element: Identifiable & Equatable>(
        old: [Element], new: [Element]
    ) -> StableMerge<Element> {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inserted = new.map(\.id).filter { oldByID[$0] == nil }
        let removed = old.map(\.id).filter { newByID[$0] == nil }
        let updated = new.filter { element in
            oldByID[element.id].map { $0 != element } ?? false
        }.map(\.id)

        let list: [Element]
        if inserted.isEmpty && removed.isEmpty {
            list = old.map { newByID[$0.id] ?? $0 }
        } else {
            list = new
        }
        return StableMerge(list: list, inserted: inserted, removed: removed, updated: updated)
    }
}
