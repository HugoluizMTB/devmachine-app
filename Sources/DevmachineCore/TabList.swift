/// An ordered list of open things, as a browser keeps its tabs: opening an
/// item that is already there changes nothing, and closing one says which
/// item to show next.
public struct TabList<Item: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var items: [Item]

    public init(_ items: [Item] = []) {
        self.items = items
    }

    public func contains(_ item: Item) -> Bool {
        items.contains(item)
    }

    public mutating func open(_ item: Item) {
        guard !items.contains(item) else { return }
        items.append(item)
    }

    /// Takes `item` out and answers what to select: `selected` when it was
    /// not the one closed, else the neighbour to its right, else to its
    /// left, else nothing.
    @discardableResult
    public mutating func close(_ item: Item, selected: Item?) -> Item? {
        guard let index = items.firstIndex(of: item) else { return selected }
        items.remove(at: index)
        guard selected == item else { return selected }
        if items.indices.contains(index) { return items[index] }
        return items.last
    }

    public mutating func removeAll(where shouldRemove: (Item) -> Bool) {
        items.removeAll(where: shouldRemove)
    }

    /// Puts `new` where `old` was; drops `old` when `new` is already open.
    public mutating func replace(_ old: Item, with new: Item) {
        guard let index = items.firstIndex(of: old) else { return }
        if items.contains(new) {
            items.remove(at: index)
        } else {
            items[index] = new
        }
    }
}
