import Foundation
import DevmachineCore

/// One tab in the strip over the terminal: a session opened this run, or a
/// file looked at from one. A file tab is a way back to that file in that
/// session; it stays until its own × is pressed, even when the viewer
/// beside the terminal is closed.
enum CenterTab: Hashable {
    case session(SidebarItem)
    case file(owner: SidebarItem, path: String)

    var owner: SidebarItem {
        switch self {
        case let .session(item): return item
        case let .file(owner, _): return owner
        }
    }

    var isSession: Bool {
        if case .session = self { return true }
        return false
    }

    var path: String? {
        if case let .file(_, path) = self { return path }
        return nil
    }
}

extension AppModel {
    func title(for tab: CenterTab) -> String {
        switch tab {
        case let .session(.session(_, name)):
            return name
        case let .session(.localSession(handle, _)):
            return localSessions.first { $0.handle == handle }?.name ?? handle
        case let .file(_, path):
            return (path as NSString).lastPathComponent
        }
    }

    /// The session tab of what is on screen; a file tab as well while the
    /// viewer shows that file beside that session.
    func isSelected(tab: CenterTab) -> Bool {
        guard activePage == nil, selection == tab.owner else { return false }
        switch tab {
        case .session:
            return true
        case let .file(_, path):
            return fileViewer?.isOpen == true && fileViewer?.path == path
        }
    }

    func harnessBadges(for item: SidebarItem) -> [HarnessBadgePresentation] {
        switch item {
        case let .session(alias, name):
            guard let session = sessions(in: alias).first(where: { $0.name == name }) else { return [] }
            return badges(for: session)
        case let .localSession(handle, _):
            guard let session = localSessions.first(where: { $0.handle == handle }) else { return [] }
            return badges(for: session)
        }
    }

    func select(tab: CenterTab) {
        if selection != tab.owner || activePage != nil {
            selection = tab.owner
        } else if appMode != .code {
            appMode = .code
        }
        guard case let .file(owner, path) = tab else { return }
        guard fileViewer?.isOpen != true || fileViewer?.path != path, let target = commandTarget(for: owner) else { return }
        fileViewer?.open(target, path: path)
    }

    /// Takes the tab off the strip. A session keeps running; a file tab
    /// also closes the viewer when it shows that file. Closing the session
    /// on screen moves to the neighbour tab, or Home when it was the last.
    func close(tab: CenterTab) {
        switch tab {
        case let .file(_, path):
            openTabs.close(tab, selected: nil)
            if fileViewer?.isOpen == true, fileViewer?.path == path { fileViewer?.close() }
        case let .session(item):
            let wasOnScreen = activePage == nil && selection == item
            openTabs.removeAll { $0.owner == item && $0 != tab }
            let next = openTabs.close(tab, selected: wasOnScreen ? tab : nil)
            guard wasOnScreen else { return }
            if let next {
                select(tab: next)
            } else {
                goHome()
            }
        }
    }

    func fileOpened(path: String) {
        guard let selection, activePage == nil else { return }
        openTabs.open(.file(owner: selection, path: path))
    }

    func dropTabs(of item: SidebarItem) {
        openTabs.removeAll { $0.owner == item }
    }

    func moveTabs(from old: SidebarItem, to new: SidebarItem) {
        for tab in openTabs.items where tab.owner == old {
            switch tab {
            case .session:
                openTabs.replace(tab, with: .session(new))
            case let .file(_, path):
                openTabs.replace(tab, with: .file(owner: new, path: path))
            }
        }
    }
}
