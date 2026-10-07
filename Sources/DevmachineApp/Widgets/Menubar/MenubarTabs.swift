import DevmachineCore

enum MenubarTabID: Hashable {
    case approvals
    case entry(String)
}

struct MenubarTab: Hashable {
    let id: MenubarTabID
    let title: String
    let systemImage: String?
}

/// The popover's tab strip, decided without SwiftUI: today's titles and
/// icons for the built-in tabs, and Approvals first while a title widget asks.
enum MenubarTabs {
    static let approvalsTitle = "Approvals"

    static func make(
        board: StackBoard, resolve: (StackEntry) -> WidgetResolution?, catalog: WidgetCatalog?, hasApprovals: Bool
    ) -> [MenubarTab] {
        let approvals = hasApprovals ? [MenubarTab(id: .approvals, title: approvalsTitle, systemImage: "hand.raised")] : []
        return approvals + board.entries.map { entry in
            let resolution = resolve(entry)
            var icon: String?
            if case let .ready(resolved)? = resolution { icon = MenuBarTab(viewKind: resolved.viewKind)?.systemImage }
            return MenubarTab(
                id: .entry(entry.id), title: MenubarTitles.title(entry, resolution: resolution, catalog: catalog),
                systemImage: icon)
        }
    }

    static func opening(_ tabs: [MenubarTab], preferred: String?) -> MenubarTabID? {
        if tabs.first?.id == .approvals { return .approvals }
        if let preferred, tabs.contains(where: { $0.id == .entry(preferred) }) { return .entry(preferred) }
        return tabs.first?.id
    }

    static func keeping(_ current: MenubarTabID?, in tabs: [MenubarTab]) -> MenubarTabID? {
        if let current, tabs.contains(where: { $0.id == current }) { return current }
        return tabs.first { $0.id != .approvals }?.id ?? tabs.first?.id
    }

    static func entryID(_ id: MenubarTabID?) -> String? {
        if case let .entry(entry)? = id { return entry }
        return nil
    }

    /// Edit mode hides the tab, so its widget stops until Done.
    static func shownEntry(_ id: MenubarTabID?, editing: Bool) -> String? {
        editing ? nil : entryID(id)
    }
}
