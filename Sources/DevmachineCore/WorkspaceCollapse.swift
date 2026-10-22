import Foundation

/// Which workspaces have their sessions folded away in the sidebar, by ssh
/// alias. A click on the workspace's name folds or unfolds it; the choice
/// is kept across launches. Only the session rows fold: a card that asks
/// for something (a host key, a login, Prepare) stays where it is.
public struct WorkspaceCollapse: Equatable, Sendable {
    public static let defaultsKey = "collapsedWorkspaces"

    public private(set) var collapsed: Set<String>

    public init(collapsed: Set<String> = []) {
        self.collapsed = collapsed
    }

    public func isCollapsed(_ alias: String) -> Bool {
        collapsed.contains(alias)
    }

    public mutating func toggle(_ alias: String) {
        set(alias, collapsed: !isCollapsed(alias))
    }

    public mutating func set(_ alias: String, collapsed isCollapsed: Bool) {
        if isCollapsed {
            collapsed.insert(alias)
        } else {
            collapsed.remove(alias)
        }
    }

    public static func showsSessions(alias: String, collapsed: WorkspaceCollapse) -> Bool {
        !collapsed.isCollapsed(alias)
    }

    /// The number shown after a folded workspace's name; nothing for none.
    public static func countLabel(_ count: Int) -> String {
        count > 0 ? String(count) : ""
    }

    public static func load(_ defaults: UserDefaults) -> WorkspaceCollapse {
        WorkspaceCollapse(collapsed: Set(defaults.stringArray(forKey: defaultsKey) ?? []))
    }

    public func save(_ defaults: UserDefaults) {
        defaults.set(collapsed.sorted(), forKey: Self.defaultsKey)
    }
}
