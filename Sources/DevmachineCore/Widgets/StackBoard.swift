import Foundation

/// How tall a widget is in a stack: a preset's rows, or as tall as its
/// content (only for a view that grows). A tab never reads its size, so it
/// keeps any other word as `written`, as the CLI keeps it.
public enum StackSize: Hashable, Sendable {
    case preset(String)
    case auto
    case written(String)

    public var text: String {
        switch self {
        case let .preset(name), let .written(name): return name
        case .auto: return "auto"
        }
    }

    public var presetName: String? {
        if case let .preset(name) = self { return name }
        return nil
    }

    public init?(text: String, contract: WidgetContract = .current) {
        if text == "auto" {
            self = .auto
        } else if contract.presets[text] != nil {
            self = .preset(text)
        } else {
            return nil
        }
    }
}

/// One widget in a sidebar. Its place is its index in the list; it has no
/// frame and no z.
public struct StackEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var with: [String: BoardScalar]
    public var inline: InlineWidget?
    public var size: StackSize?
    public var collapsed: Bool

    public init(
        id: String, type: String, with: [String: BoardScalar] = [:], inline: InlineWidget? = nil,
        size: StackSize? = nil, collapsed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.with = with
        self.inline = inline
        self.size = size
        self.collapsed = collapsed
    }

    public var isInline: Bool { inline != nil }

    public var package: String { String(type.split(separator: "/").first ?? "") }

    /// What the shared resolver reads; frame and z mean nothing in a stack.
    public var boardWidget: BoardWidget {
        BoardWidget(
            id: id, type: type, with: with, frame: BoardFrame(x: 0, y: 0, w: 1, h: 1),
            size: size?.presetName ?? BoardWidget.customSize, z: 0, inline: inline)
    }
}

public enum StackPosition: Equatable, Sendable {
    case end
    case before(String)
    case after(String)
}

/// A sidebar's board: an ordered list. Every operation is pure and says
/// whether it changed anything, so a no-op never schedules a write.
public struct StackBoard: Equatable, Sendable {
    public var surface: String
    public var entries: [StackEntry]

    public init(surface: String, entries: [StackEntry]) {
        self.surface = surface
        self.entries = entries
    }

    public func index(of id: String) -> Int? { entries.firstIndex { $0.id == id } }

    public func uniqueID(base: String) -> String {
        BoardIDs.unique(base: base, taken: Set(entries.map(\.id)))
    }

    @discardableResult
    public mutating func insert(_ entry: StackEntry, at position: StackPosition) -> Bool {
        guard index(of: entry.id) == nil, let target = slot(for: position) else { return false }
        entries.insert(entry, at: target)
        return true
    }

    @discardableResult
    public mutating func move(_ id: String, to position: StackPosition) -> Bool {
        switch position {
        case let .before(anchor) where anchor == id, let .after(anchor) where anchor == id: return false
        default: break
        }
        guard let from = index(of: id) else { return false }
        var next = self
        let entry = next.entries.remove(at: from)
        guard let target = next.slot(for: position) else { return false }
        next.entries.insert(entry, at: target)
        guard next != self else { return false }
        self = next
        return true
    }

    /// `index` is where the entry ends up, clamped to the list.
    @discardableResult
    public mutating func move(_ id: String, toIndex index: Int) -> Bool {
        guard let from = self.index(of: id) else { return false }
        let target = max(0, min(index, entries.count - 1))
        guard target != from else { return false }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: target)
        return true
    }

    @discardableResult
    public mutating func moveUp(_ id: String) -> Bool {
        guard let from = index(of: id), from > 0 else { return false }
        return move(id, toIndex: from - 1)
    }

    @discardableResult
    public mutating func moveDown(_ id: String) -> Bool {
        guard let from = index(of: id), from < entries.count - 1 else { return false }
        return move(id, toIndex: from + 1)
    }

    @discardableResult
    public mutating func remove(_ id: String) -> Bool {
        guard let at = index(of: id) else { return false }
        entries.remove(at: at)
        return true
    }

    @discardableResult
    public mutating func setCollapsed(_ id: String, _ collapsed: Bool) -> Bool {
        guard let at = index(of: id), entries[at].collapsed != collapsed else { return false }
        entries[at].collapsed = collapsed
        return true
    }

    @discardableResult
    public mutating func setSize(_ id: String, _ size: StackSize?) -> Bool {
        guard let at = index(of: id), entries[at].size != size else { return false }
        entries[at].size = size
        return true
    }

    private func slot(for position: StackPosition) -> Int? {
        switch position {
        case .end: return entries.count
        case let .before(anchor): return index(of: anchor)
        case let .after(anchor): return index(of: anchor).map { $0 + 1 }
        }
    }
}

/// The boards written when an ordered surface's file is missing or reset:
/// today's sidebar, Context tab, menu bar title and popover, in today's order.
public enum DefaultStackBoard {
    public static let package = "devmachine-app"
    public static let sidebar = "sidebar"
    public static let contextSidebar = "context-sidebar"
    public static let menubar = "menubar"
    public static let menubarPanel = "menubar-panel"
    public static let surfaces = [sidebar, contextSidebar]
    public static let menubarSurfaces = [menubar, menubarPanel]
    public static let sidebarWidgets = ["workspaces"]
    public static let contextSidebarWidgets = [
        "shortcuts", "publish-port", "monitors", "shells", "sub-agents", "todo", "pull-requests", "links",
    ]
    public static let menubarWidgets = ["brand", "open-pull-requests"]
    public static let menubarPanelWidgets = ["pull-requests-panel", "usage-panel"]

    /// A stack entry is written with `size: auto`; a slot or a tab takes none.
    public static func make(surface: String, contract: WidgetContract = .current) -> StackBoard {
        let names: [String]
        switch surface {
        case sidebar: names = sidebarWidgets
        case contextSidebar: names = contextSidebarWidgets
        case menubar: names = menubarWidgets
        case menubarPanel: names = menubarPanelWidgets
        default: names = []
        }
        let size: StackSize? = contract.layout(of: surface) == "stack" ? .auto : nil
        return StackBoard(
            surface: surface, entries: names.map { StackEntry(id: $0, type: "\(package)/\($0)", size: size) })
    }
}
