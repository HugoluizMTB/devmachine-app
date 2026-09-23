enum NavigationDestination: Hashable {
    case home
    case session(SidebarItem)
    case page(AppPage)
}

struct NavigationHistory {
    private let limit: Int
    private(set) var entries: [NavigationDestination]
    private(set) var index: Int

    init(initial: NavigationDestination, limit: Int = 10) {
        self.limit = max(1, limit)
        entries = [initial]
        index = 0
    }

    mutating func record(_ destination: NavigationDestination) {
        if entries[index] == destination { return }
        if index < entries.count - 1 {
            entries.removeSubrange((index + 1)...)
        }
        entries.append(destination)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        index = entries.count - 1
    }

    mutating func back() -> NavigationDestination? {
        guard index > 0 else { return nil }
        index -= 1
        return entries[index]
    }

    mutating func forward() -> NavigationDestination? {
        guard index + 1 < entries.count else { return nil }
        index += 1
        return entries[index]
    }
}
