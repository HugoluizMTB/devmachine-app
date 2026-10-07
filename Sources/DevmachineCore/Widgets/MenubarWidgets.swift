import Foundation

/// The devmachine-app widgets the menu bar draws by default. They resolve
/// before the catalog is read, so a missing CLI or packages release never
/// empties the title or the popover; a catalog entry of the same name wins.
public enum AppMenubarWidgets {
    public static let package = DefaultStackBoard.package

    private struct Spec {
        let provider: String
        let view: WidgetValue
        let layout: String
        let surface: String
        let title: String
        let summary: String
    }

    private static let specs: [String: Spec] = [
        "brand": Spec(
            provider: "app/brand", view: .object(["kind": .string("app.brand")]), layout: "slot",
            surface: DefaultStackBoard.menubar, title: "Devmachine mark", summary: "The ❯_ mark."),
        "open-pull-requests": Spec(
            provider: "app/open-pull-requests",
            view: .object(["kind": .string("number"), "hide_zero": .bool(true)]), layout: "slot",
            surface: DefaultStackBoard.menubar, title: "Open pull requests",
            summary: "How many of your pull requests are open; hidden at 0."),
        "pull-requests-panel": Spec(
            provider: "app/pull-requests-panel", view: .object(["kind": .string("app.pull-requests-panel")]),
            layout: "tabs", surface: DefaultStackBoard.menubarPanel, title: "Pull Requests",
            summary: "Your open pull requests, by organisation."),
        "usage-panel": Spec(
            provider: "app/usage-panel", view: .object(["kind": .string("app.usage-panel")]), layout: "tabs",
            surface: DefaultStackBoard.menubarPanel, title: "Usage",
            summary: "Coding harness usage, one column per harness."),
    ]

    public static var providers: [String: String] { specs.mapValues(\.provider) }
    public static let viewKinds: Set<String> = ["app.brand", "app.pull-requests-panel", "app.usage-panel"]
    /// The app's title for each of its views; a tab drawn by one takes it.
    public static let viewTitles: [String: String] = [
        "app.brand": "Devmachine mark", "app.pull-requests-panel": "Pull Requests", "app.usage-panel": "Usage",
    ]

    public static func title(_ widget: String) -> String? { specs[widget]?.title }

    public static func catalogWidget(_ widget: String) -> CatalogWidget? {
        guard let spec = specs[widget], let kind = spec.view["kind"]?.string else { return nil }
        return CatalogWidget(
            name: "\(package)/\(widget)", summary: spec.summary, requiresEngine: ">= 1.4", fits: [spec.layout],
            source: CatalogSource(name: spec.provider, every: "60s"), viewKind: kind, sizes: [], defaultSize: "",
            places: [spec.surface], surfaces: [spec.surface], origin: "app", view: spec.view, single: true)
    }

    public static var all: [CatalogWidget] { specs.keys.sorted().compactMap(catalogWidget) }
}

/// What the menu bar title adds to the shared rules: a short list of views,
/// no streams, and a 30 s floor, because its widgets run with no window open.
public enum MenubarSlotRules {
    public static func refusal(_ resolved: ResolvedWidget, contract: WidgetContract = .current) -> String? {
        if !contract.slotEntry.views.contains(resolved.viewKind) {
            return "the \(resolved.viewKind) view cannot be drawn in the menu bar"
        }
        if resolved.source?.every == .continuous {
            return "a stream never ends, so it cannot run in the menu bar: use mode: poll"
        }
        return nil
    }

    public static func floored(_ resolved: ResolvedWidget, contract: WidgetContract = .current) -> ResolvedWidget {
        let floor = contract.slotFloor
        var source = resolved.source
        if let current = source, case let .interval(seconds) = current.every, seconds < floor {
            source = current.withEvery(.interval(floor))
        }
        let every = resolved.every > 0 ? max(floor, resolved.every) : resolved.every
        return ResolvedWidget(
            widget: resolved.widget, provider: resolved.provider, viewKind: resolved.viewKind,
            arguments: resolved.arguments, every: every, minimum: resolved.minimum, source: source, title: resolved.title)
    }
}

/// A tab's or a slot's name in the popover: the built-in title, the inline
/// title, the catalog's, or the placeholder's.
public enum MenubarTitles {
    public static func title(_ entry: StackEntry, resolution: WidgetResolution?, catalog: WidgetCatalog?) -> String {
        if let inline = entry.inline { return inline.title }
        if case let .ready(resolved)? = resolution, let title = AppMenubarWidgets.viewTitles[resolved.viewKind] {
            return title
        }
        if entry.package == AppMenubarWidgets.package,
           let title = AppMenubarWidgets.title(String(entry.type.dropFirst(entry.package.count + 1))) {
            return title
        }
        switch resolution {
        case .ready?, nil: return WidgetTitle.make(type: entry.type, in: catalog)
        case let .some(other): return WidgetResolutionCopy.title(other)
        }
    }
}
