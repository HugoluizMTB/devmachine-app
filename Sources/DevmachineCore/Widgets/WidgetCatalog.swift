import Foundation

/// `devmachine widgets list --format json`: every widget of the pinned
/// packages release and of the person's own packages, already validated by
/// the CLI. A widget that failed validation is in `problems`, not `widgets`.
public struct WidgetCatalog: Decodable, Equatable, Sendable {
    public let engine: String
    public let packagesRelease: String
    public let widgets: [CatalogWidget]
    public let problems: [CatalogProblem]
    /// Every package provider the CLI found, sorted by name; nil from a CLI
    /// older than engine 1.3, which lists none.
    public let providers: [CatalogProvider]?
    /// The last read failed, so the commits here may be older than what
    /// `packages update` installed since; third-party code waits for a fresh one.
    public var isStale = false

    enum CodingKeys: String, CodingKey {
        case engine, widgets, problems, providers
        case packagesRelease = "packages_release"
    }

    public init(
        engine: String, packagesRelease: String, widgets: [CatalogWidget], problems: [CatalogProblem] = [],
        providers: [CatalogProvider]? = nil
    ) {
        self.engine = engine
        self.packagesRelease = packagesRelease
        self.widgets = widgets
        self.problems = problems
        self.providers = providers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try c.decode(String.self, forKey: .engine)
        packagesRelease = try c.decodeIfPresent(String.self, forKey: .packagesRelease) ?? ""
        widgets = try c.decodeIfPresent([CatalogWidget].self, forKey: .widgets) ?? []
        problems = try c.decodeIfPresent([CatalogProblem].self, forKey: .problems) ?? []
        providers = try c.decodeIfPresent([String: LenientProviderSpec].self, forKey: .providers)?
            .compactMap { entry in
                entry.value.spec.map {
                    CatalogProvider(name: entry.key, spec: $0, trust: entry.value.trust, packageSource: entry.value.packageSource)
                }
            }
            .sorted { $0.name < $1.name }
    }

    public var packageProviderIndex: PackageProviderIndex {
        var specs: [String: PackageProviderSpec] = [:]
        for widget in widgets {
            if let spec = widget.packageProvider { specs[widget.source.name] = spec }
        }
        for provider in providers ?? [] { specs[provider.name] = provider.spec }
        guard providers != nil else { return PackageProviderIndex(providers: specs, packages: [], isComplete: false) }
        let packages = Set(widgets.map(\.package))
            .union(specs.keys.compactMap { PackageProviderName.parts($0)?.package })
        return PackageProviderIndex(providers: specs, packages: packages, isComplete: !packagesRelease.isEmpty)
    }

    public func stale() -> WidgetCatalog {
        var copy = self
        copy.isStale = true
        return copy
    }

    public static func decode(_ data: Data) throws -> WidgetCatalog {
        try JSONDecoder().decode(WidgetCatalog.self, from: data)
    }

    public func widget(named name: String) -> CatalogWidget? {
        widgets.first { $0.name == name }
    }
}

/// One entry of the catalog's top-level `providers`, the list a widget
/// written in a board is checked against.
public struct CatalogProvider: Equatable, Sendable {
    public let name: String
    public let spec: PackageProviderSpec
    /// nil from a CLI that writes no trust for a provider.
    public let trust: WidgetTrust?
    public let packageSource: CatalogPackageSource?

    public init(
        name: String, spec: PackageProviderSpec, trust: WidgetTrust? = nil, packageSource: CatalogPackageSource? = nil
    ) {
        self.name = name
        self.spec = spec
        self.trust = trust
        self.packageSource = packageSource
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

/// `raw` is the whole source as the CLI printed it; the four provider
/// fields stay for the engine 1.0 code that reads them.
public struct CatalogSource: Decodable, Equatable, Sendable {
    public var kind: String
    public var name: String
    public var with: [String: String]
    public var every: String
    public var raw: WidgetValue

    public init(kind: String = "provider", name: String, with: [String: String] = [:], every: String) {
        self.kind = kind
        self.name = name
        self.with = with
        self.every = every
        raw = .object([
            "kind": .string(kind), "name": .string(name),
            "with": .object(with.mapValues(WidgetValue.string)), "every": .string(every),
        ])
    }

    public init(raw: WidgetValue) {
        self.raw = raw
        kind = raw["kind"]?.string ?? ""
        name = raw["name"]?.string ?? ""
        with = raw["with"]?.object?.mapValues(\.text) ?? [:]
        every = raw["every"]?.text ?? ""
    }

    public init(from decoder: Decoder) throws {
        let value = try WidgetValue(from: decoder)
        guard value["kind"]?.string != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "source.kind is missing"))
        }
        self.init(raw: value)
    }
}

/// Where a widget's code comes from. Only `thirdParty` code asks before it
/// runs: an official release and a hand-written package are the owner's own.
public enum WidgetTrust: String, Sendable {
    case official
    case local
    case thirdParty = "third-party"

    /// An older CLI writes no trust; a word this app does not know asks.
    public static func read(_ text: String?, origin: String) -> WidgetTrust {
        guard let text else { return origin == "release" ? .official : .local }
        return WidgetTrust(rawValue: text) ?? .thirdParty
    }

    /// A `trust` that is there but unreadable, or a package source without
    /// one, asks: neither may pass for the owner's own code.
    fileprivate static func decode(from c: KeyedDecodingContainer<CatalogWidget.CodingKeys>, origin: String) -> WidgetTrust {
        if c.contains(.trust) {
            return read((try? c.decodeIfPresent(String.self, forKey: .trust)) ?? "", origin: origin)
        }
        return c.contains(.packageSource) ? .thirdParty : read(nil, origin: origin)
    }
}

/// One provider of the catalog's map; an entry that does not read is left
/// out instead of failing the whole catalog.
private struct LenientProviderSpec: Decodable {
    let spec: PackageProviderSpec?
    let trust: WidgetTrust?
    let packageSource: CatalogPackageSource?

    enum CodingKeys: String, CodingKey {
        case trust
        case packageSource = "package_source"
    }

    init(from decoder: Decoder) throws {
        spec = try? PackageProviderSpec(from: decoder)
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        packageSource = try? c?.decodeIfPresent(CatalogPackageSource.self, forKey: .packageSource)
        if let c, c.contains(.trust) {
            trust = WidgetTrust.read((try? c.decodeIfPresent(String.self, forKey: .trust)) ?? "", origin: "")
        } else {
            trust = c?.contains(.packageSource) == true ? .thirdParty : nil
        }
    }
}

/// `.devmachine-source.yml` of a package installed from a git URL.
public struct CatalogPackageSource: Decodable, Equatable, Sendable {
    public let url: String
    public let ref: String
    public let commit: String

    public init(url: String, ref: String, commit: String) {
        self.url = url
        self.ref = ref
        self.commit = commit
    }

    enum CodingKeys: String, CodingKey { case url, ref, commit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? ""
        commit = try c.decodeIfPresent(String.self, forKey: .commit) ?? ""
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
    public var view: WidgetValue
    public var packagePath: String
    public var sizes: [String]
    public var defaultSize: String
    public var places: [String]
    public var single: Bool
    public var surfaces: [String]
    public var available: Bool
    public var unavailableReason: String
    public var trust: WidgetTrust
    public var packageSource: CatalogPackageSource?
    public var packageProvider: PackageProviderSpec?

    public init(
        name: String, summary: String = "", requiresEngine: String = ">= 1.0",
        fits: [String] = ["canvas", "stack", "slot"], context: [String: String] = [:],
        inputs: [String: CatalogInput] = [:], source: CatalogSource, viewKind: String,
        sizes: [String], defaultSize: String, places: [String] = ["home"], surfaces: [String] = ["home"],
        available: Bool = true, unavailableReason: String = "",
        origin: String = "release", version: String = "", path: String = "",
        view: WidgetValue? = nil, packagePath: String = "", single: Bool = false,
        trust: WidgetTrust? = nil, packageSource: CatalogPackageSource? = nil, packageProvider: PackageProviderSpec? = nil
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
        self.view = view ?? .object(["kind": .string(viewKind)])
        self.packagePath = packagePath
        self.single = single
        self.trust = trust ?? WidgetTrust.read(nil, origin: origin)
        self.packageSource = packageSource
        self.packageProvider = packageProvider
    }

    enum CodingKeys: String, CodingKey {
        case name, package, widget, origin, version, path, summary, fits, context, inputs, source, view
        case sizes, places, single, surfaces, available, trust
        case packageSource = "package_source"
        case packageProvider = "provider"
        case requiresEngine = "requires_engine"
        case defaultSize = "default_size"
        case unavailableReason = "unavailable_reason"
        case packagePath = "package_path"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        package = try c.decode(String.self, forKey: .package)
        widget = try c.decode(String.self, forKey: .widget)
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? ""
        packageSource = try? c.decodeIfPresent(CatalogPackageSource.self, forKey: .packageSource)
        packageProvider = try? c.decodeIfPresent(PackageProviderSpec.self, forKey: .packageProvider)
        trust = c.contains(.packageProvider) && packageProvider == nil
            ? .thirdParty : WidgetTrust.decode(from: c, origin: origin)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        requiresEngine = try c.decodeIfPresent(String.self, forKey: .requiresEngine) ?? ""
        fits = try c.decodeIfPresent([String].self, forKey: .fits) ?? []
        context = try c.decodeIfPresent([String: String].self, forKey: .context) ?? [:]
        inputs = try c.decodeIfPresent([String: CatalogInput].self, forKey: .inputs) ?? [:]
        source = try c.decode(CatalogSource.self, forKey: .source)
        view = try c.decode(WidgetValue.self, forKey: .view)
        guard let kind = view["kind"]?.string else {
            throw DecodingError.dataCorruptedError(forKey: .view, in: c, debugDescription: "view.kind is missing")
        }
        viewKind = kind
        packagePath = try c.decodeIfPresent(String.self, forKey: .packagePath) ?? ""
        sizes = try c.decodeIfPresent([String].self, forKey: .sizes) ?? []
        defaultSize = try c.decodeIfPresent(String.self, forKey: .defaultSize) ?? ""
        places = try c.decodeIfPresent([String].self, forKey: .places) ?? []
        single = try c.decodeIfPresent(Bool.self, forKey: .single) ?? false
        surfaces = try c.decodeIfPresent([String].self, forKey: .surfaces) ?? []
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
        unavailableReason = try c.decodeIfPresent(String.self, forKey: .unavailableReason) ?? ""
    }
}

extension CatalogWidget {
    /// A widget written in a board has no catalog entry; this stands in for
    /// one so sizes, presets and titles work the same way.
    public static func inline(id: String, title: String, sizes: [String], fits: [String], viewKind: String) -> CatalogWidget {
        CatalogWidget(
            name: "inline/\(id)", summary: title, requiresEngine: "", fits: fits.isEmpty ? ["canvas", "stack", "slot"] : fits,
            source: CatalogSource(raw: .object([:])), viewKind: viewKind,
            sizes: sizes.isEmpty ? WidgetContract.presetOrder : sizes, defaultSize: sizes.first ?? "medium",
            places: [], surfaces: ["home"], origin: "board")
    }
}
