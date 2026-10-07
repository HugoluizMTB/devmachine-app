import Foundation

/// `devmachine widgets list --format json`: every widget of the pinned
/// packages release and of the person's own packages, already validated by
/// the CLI. A widget that failed validation is in `problems`, not `widgets`.
public struct WidgetCatalog: Decodable, Equatable, Sendable {
    public let engine: String
    public let packagesRelease: String
    public let widgets: [CatalogWidget]
    public let problems: [CatalogProblem]

    enum CodingKeys: String, CodingKey {
        case engine, widgets, problems
        case packagesRelease = "packages_release"
    }

    public init(engine: String, packagesRelease: String, widgets: [CatalogWidget], problems: [CatalogProblem] = []) {
        self.engine = engine
        self.packagesRelease = packagesRelease
        self.widgets = widgets
        self.problems = problems
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try c.decode(String.self, forKey: .engine)
        packagesRelease = try c.decodeIfPresent(String.self, forKey: .packagesRelease) ?? ""
        widgets = try c.decodeIfPresent([CatalogWidget].self, forKey: .widgets) ?? []
        problems = try c.decodeIfPresent([CatalogProblem].self, forKey: .problems) ?? []
    }

    public static func decode(_ data: Data) throws -> WidgetCatalog {
        try JSONDecoder().decode(WidgetCatalog.self, from: data)
    }

    public func widget(named name: String) -> CatalogWidget? {
        widgets.first { $0.name == name }
    }
}

public struct CatalogProblem: Decodable, Equatable, Sendable {
    public let path: String
    public let message: String
}

public struct CatalogInput: Decodable, Equatable, Sendable {
    public let type: String
    public let defaultValue: BoardScalar?
    public let summary: String

    enum CodingKeys: String, CodingKey {
        case type, summary
        case defaultValue = "default"
    }

    public init(type: String, defaultValue: BoardScalar?, summary: String) {
        self.type = type
        self.defaultValue = defaultValue
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "string"
        defaultValue = try c.decodeIfPresent(BoardScalar.self, forKey: .defaultValue)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
    }
}

public struct CatalogSource: Decodable, Equatable, Sendable {
    public var kind: String
    public var name: String
    public var with: [String: String]
    public var every: String

    public init(kind: String = "provider", name: String, with: [String: String] = [:], every: String) {
        self.kind = kind
        self.name = name
        self.with = with
        self.every = every
    }

    enum CodingKeys: String, CodingKey { case kind, name, with, every }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        with = (try c.decodeIfPresent([String: BoardScalar].self, forKey: .with) ?? [:]).mapValues(\.text)
        every = try c.decodeIfPresent(String.self, forKey: .every) ?? ""
    }
}

public struct CatalogWidget: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { name }

    public let name: String
    public let package: String
    public let widget: String
    public var origin: String
    public var version: String
    public var path: String
    public var summary: String
    public var requiresEngine: String
    public var fits: [String]
    public var context: [String: String]
    public var inputs: [String: CatalogInput]
    public var source: CatalogSource
    public var viewKind: String
    public var sizes: [String]
    public var defaultSize: String
    public var places: [String]
    public var surfaces: [String]
    public var available: Bool
    public var unavailableReason: String

    public init(
        name: String, summary: String = "", requiresEngine: String = ">= 1.0",
        fits: [String] = ["canvas", "stack", "slot"], context: [String: String] = [:],
        inputs: [String: CatalogInput] = [:], source: CatalogSource, viewKind: String,
        sizes: [String], defaultSize: String, places: [String] = ["home"], surfaces: [String] = ["home"],
        available: Bool = true, unavailableReason: String = "",
        origin: String = "release", version: String = "", path: String = ""
    ) {
        let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
        self.name = name
        self.package = parts.first ?? name
        self.widget = parts.count > 1 ? parts[1] : name
        self.summary = summary
        self.requiresEngine = requiresEngine
        self.fits = fits
        self.context = context
        self.inputs = inputs
        self.source = source
        self.viewKind = viewKind
        self.sizes = sizes
        self.defaultSize = defaultSize
        self.places = places
        self.surfaces = surfaces
        self.available = available
        self.unavailableReason = unavailableReason
        self.origin = origin
        self.version = version
        self.path = path
    }

    private struct View: Decodable { let kind: String }

    enum CodingKeys: String, CodingKey {
        case name, package, widget, origin, version, path, summary, fits, context, inputs, source, view
        case sizes, places, surfaces, available
        case requiresEngine = "requires_engine"
        case defaultSize = "default_size"
        case unavailableReason = "unavailable_reason"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        package = try c.decode(String.self, forKey: .package)
        widget = try c.decode(String.self, forKey: .widget)
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        requiresEngine = try c.decodeIfPresent(String.self, forKey: .requiresEngine) ?? ""
        fits = try c.decodeIfPresent([String].self, forKey: .fits) ?? []
        context = try c.decodeIfPresent([String: String].self, forKey: .context) ?? [:]
        inputs = try c.decodeIfPresent([String: CatalogInput].self, forKey: .inputs) ?? [:]
        source = try c.decode(CatalogSource.self, forKey: .source)
        viewKind = try c.decode(View.self, forKey: .view).kind
        sizes = try c.decodeIfPresent([String].self, forKey: .sizes) ?? []
        defaultSize = try c.decodeIfPresent(String.self, forKey: .defaultSize) ?? ""
        places = try c.decodeIfPresent([String].self, forKey: .places) ?? []
        surfaces = try c.decodeIfPresent([String].self, forKey: .surfaces) ?? []
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
        unavailableReason = try c.decodeIfPresent(String.self, forKey: .unavailableReason) ?? ""
    }
}
