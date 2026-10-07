import Foundation

/// The devmachine-app widgets the sidebars draw by default. They resolve
/// even before the catalog is read, so a missing CLI or packages release
/// never empties the sidebar; a catalog entry of the same name wins.
public enum AppStackWidgets {
    public static let package = DefaultStackBoard.package
    public static let providers: [String: String] = [
        "workspaces": "app/workspaces", "shortcuts": "app/shortcuts", "publish-port": "app/publish-port",
        "monitors": "app/session-context", "shells": "app/session-context", "sub-agents": "app/session-context",
        "todo": "app/session-context", "pull-requests": "app/session-context", "links": "app/session-context",
    ]
    public static let viewKinds = Set(providers.keys.map { "app.\($0)" })
    public static let titles: [String: String] = [
        "workspaces": "WORKSPACES", "shortcuts": "SHORTCUTS", "publish-port": "PUBLISH A PORT",
        "monitors": "MONITORS", "shells": "SHELLS", "sub-agents": "SUB-AGENTS", "todo": "TODO",
        "pull-requests": "PULL REQUESTS", "links": "LINKS",
    ]
    private static let summaries: [String: String] = [
        "workspaces": "Your workspaces and their sessions.",
        "shortcuts": "Buttons that send a command to the selected session.",
        "publish-port": "Publish a port of the selected workspace.",
        "monitors": "What the selected session watches.",
        "shells": "Background shells of the selected session.",
        "sub-agents": "Sub-agents of the selected session.",
        "todo": "The selected session's plan.",
        "pull-requests": "Pull requests the selected session named.",
        "links": "Links the selected session named.",
    ]

    public static func catalogWidget(_ widget: String) -> CatalogWidget? {
        guard let provider = providers[widget] else { return nil }
        let required = WidgetContract.current.requiredContext(ofProvider: provider)
        let surfaces = required.isEmpty
            ? [DefaultStackBoard.contextSidebar, DefaultStackBoard.sidebar] : [DefaultStackBoard.contextSidebar]
        let places = DefaultStackBoard.sidebarWidgets.contains(widget)
            ? [DefaultStackBoard.sidebar] : [DefaultStackBoard.contextSidebar]
        return CatalogWidget(
            name: "\(package)/\(widget)", summary: summaries[widget] ?? "", requiresEngine: ">= 1.2", fits: ["stack"],
            context: Dictionary(uniqueKeysWithValues: required.map { ($0, "required") }),
            source: CatalogSource(name: provider, every: "5s"), viewKind: "app.\(widget)", sizes: [], defaultSize: "",
            places: places, surfaces: surfaces, origin: "app", single: widget == "workspaces")
    }

    public static var all: [CatalogWidget] { providers.keys.sorted().compactMap(catalogWidget) }
}

/// The catalog a stack reads: the CLI's, plus every built-in app widget it
/// does not list itself.
public enum StackCatalog {
    public static func merged(_ catalog: WidgetCatalog?, contract: WidgetContract = .current) -> WidgetCatalog {
        let known = catalog?.widgets ?? []
        let names = Set(known.map(\.name))
        var merged = WidgetCatalog(
            engine: catalog?.engine ?? contract.engine, packagesRelease: catalog?.packagesRelease ?? "",
            widgets: known + (AppStackWidgets.all + AppMenubarWidgets.all).filter { !names.contains($0.name) },
            problems: catalog?.problems ?? [], providers: catalog?.providers)
        merged.isStale = catalog?.isStale ?? false
        return merged
    }
}

/// How a stack surface reads in copy, the way the CLI writes it ("the
/// context-sidebar area"), and the board file it lives in.
public enum StackArea {
    public static func name(_ surface: String) -> String { "the \(surface) area" }
    public static func sentenceName(_ surface: String) -> String { "The \(surface) area" }
    public static func fileName(_ surface: String) -> String { "\(surface).yml" }
}

/// A stack entry becomes something to draw, a placeholder with the CLI's
/// reason, or nil while a package widget waits for the catalog.
public enum StackResolution {
    public static func resolve(
        _ entry: StackEntry, on board: StackBoard, catalog: WidgetCatalog?, contract: WidgetContract = .current
    ) -> WidgetResolution? {
        let resolution = layoutFree(entry, on: board, catalog: catalog, contract: contract)
        guard contract.layout(of: board.surface) == "slot", case let .ready(resolved)? = resolution else { return resolution }
        if let reason = MenubarSlotRules.refusal(resolved, contract: contract) {
            return .refused(type: entry.isInline ? entry.id : entry.type, reason: "\(entry.id): \(reason)")
        }
        return .ready(MenubarSlotRules.floored(resolved, contract: contract))
    }

    private static func layoutFree(
        _ entry: StackEntry, on board: StackBoard, catalog: WidgetCatalog?, contract: WidgetContract
    ) -> WidgetResolution? {
        if entry.isInline { return WidgetResolution.resolveInline(entry.boardWidget, catalog: catalog, contract: contract) }
        let merged = StackCatalog.merged(catalog, contract: contract)
        if catalog == nil, merged.widget(named: entry.type) == nil { return nil }
        let resolution = WidgetResolution.resolve(entry.boardWidget, in: merged, contract: contract)
        guard case let .ready(resolved) = resolution else { return resolution }
        if let reason = refusal(entry, resolved: resolved, board: board, contract: contract) {
            return .refused(type: entry.type, reason: reason)
        }
        return resolution
    }

    /// The board file alone cannot show these, so the codec lets them
    /// through; the order is the one the CLI reports them in.
    private static func refusal(
        _ entry: StackEntry, resolved: ResolvedWidget, board: StackBoard, contract: WidgetContract
    ) -> String? {
        let widget = resolved.widget
        let sizes = widget.sizes.isEmpty ? WidgetContract.presetOrder : widget.sizes
        let layout = contract.layout(of: board.surface)
        if layout == "stack" {
            switch entry.size {
            case .auto? where !contract.viewGrows(resolved.viewKind):
                return "size auto follows the content, and the \(resolved.viewKind) view does not grow: use "
                    + sizes.joined(separator: ", ")
            case let .preset(name)? where !sizes.contains(name):
                return "size \"\(name)\" in a sidebar is auto or one of \(sizes.joined(separator: ", "))"
            default:
                break
            }
        }
        let surface = contract.surfaces[board.surface]
        if !widget.fits.contains(layout) {
            return "\(entry.type) does not fit \(StackArea.name(board.surface)): its fits has no \(layout)"
        }
        if layout == "slot", let problem = MenubarSlotRules.viewProblem(resolved.viewKind, contract: contract) {
            return "\(entry.id): \(problem)"
        }
        let given = Set(surface?.context.keys.map { $0 } ?? [])
        let needed = contract.requiredContext(ofProvider: resolved.provider)
            .union(widget.context.filter { $0.value == "required" }.keys)
        if let missing = needed.subtracting(given).sorted().first {
            return "\(entry.type) needs context.\(missing), which \(StackArea.name(board.surface)) does not give"
        }
        if widget.single, let first = board.entries.first(where: { $0.type == entry.type }), first.id != entry.id {
            return "\(entry.type) goes on a board once, and \(first.id) already has it"
        }
        return nil
    }
}

/// What an ordered surface's "Add widget" gallery offers: widgets that fit
/// its layout (and, in the menu bar, draw one line), and why one is blocked.
public enum StackGallery {
    public static func entries(
        _ catalog: WidgetCatalog?, surface: String, contract: WidgetContract = .current
    ) -> [CatalogWidget] {
        let layout = contract.layout(of: surface)
        return WidgetGallery.entries(StackCatalog.merged(catalog, contract: contract), surface: surface).filter { widget in
            widget.fits.contains(layout) && (layout != "slot" || contract.slotEntry.views.contains(widget.viewKind))
        }
    }

    public static func isFull(_ board: StackBoard, contract: WidgetContract = .current) -> Bool {
        contract.layout(of: board.surface) == "slot" && board.entries.count >= contract.slotMax
    }

    public static func fullReason(_ board: StackBoard, contract: WidgetContract = .current) -> String? {
        isFull(board, contract: contract) ? "The menu bar holds \(contract.slotMax) widgets" : nil
    }

    public static func blockedReason(
        for widget: CatalogWidget, on board: StackBoard, contract: WidgetContract = .current
    ) -> String? {
        if let full = fullReason(board, contract: contract) { return full }
        guard widget.single, board.entries.contains(where: { $0.type == widget.name }) else { return nil }
        return "Already in \(StackArea.name(board.surface))"
    }
}
