import Foundation

public enum PackageTab: String, CaseIterable, Sendable {
    case catalog, local, installed

    public var title: String {
        switch self {
        case .catalog: return "Catalog"
        case .local: return "Local"
        case .installed: return "Installed"
        }
    }
}

public struct PackageFilter: Equatable, Sendable {
    public static let otherCategory = "Other"

    public var tab: PackageTab
    public var query: String
    public var categories: Set<String>
    public var scope: String?

    public init(tab: PackageTab = .catalog, query: String = "", categories: Set<String> = [], scope: String? = nil) {
        self.tab = tab
        self.query = query
        self.categories = categories
        self.scope = scope
    }

    /// `statuses` is nil when no single target is chosen: then installed
    /// means named by any machine or workspace.
    public func apply(_ entries: [PackageEntry], statuses: [String: PackageStatus]?) -> [PackageEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            switch tab {
            case .catalog: guard !entry.isLocal else { return false }
            case .local: guard entry.isLocal else { return false }
            case .installed:
                let installed = statuses.map { ($0[entry.name] ?? .available).isInstalled } ?? !entry.installedOn.isEmpty
                guard installed else { return false }
            }
            if !categories.isEmpty, !categories.contains(entry.categoryTitle) { return false }
            if let scope, entry.scope != scope { return false }
            if !needle.isEmpty, !entry.name.lowercased().contains(needle), !entry.summary.lowercased().contains(needle) {
                return false
            }
            return true
        }
    }

    public static func categories(in entries: [PackageEntry]) -> [String] {
        let all = Set(entries.map(\.categoryTitle))
        return all.subtracting([otherCategory]).sorted() + (all.contains(otherCategory) ? [otherCategory] : [])
    }
}
