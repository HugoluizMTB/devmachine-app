import Foundation

/// The order the person dragged the sidebar into. Workspaces are keyed by
/// alias, compared without case like the hidden list; sessions by their tmux
/// name or local handle, inside their own workspace only. Anything without a
/// saved place keeps the order it arrived in, after the saved ones.
public struct SidebarOrder: Codable, Equatable, Sendable {
    public private(set) var savedWorkspaces: [String]
    public private(set) var savedSessions: [String: [String]]

    public init(workspaces: [String] = [], sessions: [String: [String]] = [:]) {
        self.savedWorkspaces = workspaces
        self.savedSessions = sessions
    }

    public func workspaces(_ live: [String]) -> [String] {
        workspaces(live, id: { $0 })
    }

    public func workspaces<T>(_ live: [T], id: (T) -> String) -> [T] {
        Self.ordered(live, saved: savedWorkspaces.map { $0.lowercased() }, id: { id($0).lowercased() })
    }

    public func sessions(_ live: [String], in alias: String) -> [String] {
        sessions(live, in: alias, id: { $0 })
    }

    public func sessions<T>(_ live: [T], in alias: String, id: (T) -> String) -> [T] {
        Self.ordered(live, saved: savedSessions[sessionKey(alias)] ?? [], id: id)
    }

    public mutating func moveWorkspace(_ alias: String, onto target: String, live: [String]) {
        let current = workspaces(live).map { $0.lowercased() }
        guard let moved = Self.moving(alias.lowercased(), onto: target.lowercased(), in: current) else { return }
        savedWorkspaces = moved
    }

    public mutating func moveSession(_ id: String, onto target: String, in alias: String, live: [String]) {
        guard let moved = Self.moving(id, onto: target, in: sessions(live, in: alias)) else { return }
        savedSessions[sessionKey(alias)] = moved
    }

    public mutating func removeWorkspace(_ alias: String) {
        let key = alias.lowercased()
        savedWorkspaces.removeAll { $0.lowercased() == key }
        savedSessions[key] = nil
    }

    public mutating func keepWorkspaces(_ aliases: [String]) {
        let kept = Set(aliases.map { $0.lowercased() })
        savedWorkspaces.removeAll { !kept.contains($0.lowercased()) }
        savedSessions = savedSessions.filter { kept.contains($0.key) }
    }

    public mutating func removeSession(_ id: String, in alias: String) {
        keepSessions(Set(savedSessions[sessionKey(alias)] ?? []).subtracting([id]), in: alias)
    }

    public mutating func keepSessions(_ ids: some Collection<String>, in alias: String) {
        let key = sessionKey(alias)
        guard let saved = savedSessions[key] else { return }
        let kept = saved.filter(Set(ids).contains)
        savedSessions[key] = kept.isEmpty ? nil : kept
    }

    public mutating func renameSession(_ old: String, to new: String, in alias: String) {
        let key = sessionKey(alias)
        guard let index = savedSessions[key]?.firstIndex(of: old) else { return }
        savedSessions[key]?[index] = new
    }

    private func sessionKey(_ alias: String) -> String { alias.lowercased() }

    private static func ordered<T>(_ live: [T], saved: [String], id: (T) -> String) -> [T] {
        let rank = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return live.enumerated().sorted { a, b in
            switch (rank[id(a.element)], rank[id(b.element)]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Dropping onto a row takes that row's place, so a move down lands after
    /// the target and a move up lands before it.
    private static func moving(_ id: String, onto target: String, in current: [String]) -> [String]? {
        guard id != target,
              let from = current.firstIndex(of: id),
              let to = current.firstIndex(of: target)
        else { return nil }
        var next = current
        next.remove(at: from)
        next.insert(id, at: to)
        return next
    }
}

/// What a sidebar drag carries: a whole workspace, or one session inside it.
public enum SidebarDragItem: Equatable, Hashable, Sendable {
    case workspace(String)
    case session(String, in: String)

    public var alias: String {
        switch self {
        case let .workspace(alias), let .session(_, alias): return alias
        }
    }

    private static let prefix = "devmachine-sidebar"

    /// The text the drag pasteboard holds. Prefixed so a drop from anywhere
    /// else is never read as a sidebar move.
    public var token: String {
        switch self {
        case let .workspace(alias): return [Self.prefix, "workspace", alias].joined(separator: "\n")
        case let .session(id, alias): return [Self.prefix, "session", alias, id].joined(separator: "\n")
        }
    }

    public init?(token: String) {
        let parts = token.components(separatedBy: "\n")
        switch (parts.first, parts.count) {
        case (Self.prefix, 3) where parts[1] == "workspace": self = .workspace(parts[2])
        case (Self.prefix, 4) where parts[1] == "session": self = .session(parts[3], in: parts[2])
        default: return nil
        }
    }
}

public enum SidebarDrop {
    public enum Action: Equatable, Sendable {
        case moveWorkspace(String, onto: String)
        case moveSession(String, onto: String, in: String)
        /// Allowed, with nothing to move: a session over its own header.
        case stay
        /// A session over another workspace. It never changes workspace.
        case refuse
    }

    public static func action(dragging: SidebarDragItem, over target: SidebarDragItem) -> Action {
        switch dragging {
        case let .workspace(alias):
            return .moveWorkspace(alias, onto: target.alias)
        case let .session(id, alias):
            guard alias.lowercased() == target.alias.lowercased() else { return .refuse }
            guard case let .session(targetID, _) = target else { return .stay }
            return .moveSession(id, onto: targetID, in: alias)
        }
    }
}
