import Foundation

public struct EngineVersion: Comparable, Hashable, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let major = Int(parts[0]) else { return nil }
        let minor = parts.count == 2 ? Int(parts[1]) : 0
        guard let minor else { return nil }
        self.init(major: major, minor: minor)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.major, lhs.minor) < (rhs.major, rhs.minor) }
}

/// A widget's `requires.engine`: comma-separated terms that must all hold.
public struct EngineConstraint: Equatable, Sendable {
    struct Term: Equatable, Sendable {
        let op: String
        let version: EngineVersion
    }

    let terms: [Term]

    private static let operators = [">=", "<=", "==", ">", "<", "="]

    public static func parse(_ text: String) -> EngineConstraint? {
        let pieces = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !pieces.isEmpty else { return nil }
        var terms: [Term] = []
        for piece in pieces {
            let op = operators.first { piece.hasPrefix($0) } ?? "="
            let rest = piece.hasPrefix(op) ? String(piece.dropFirst(op.count)) : piece
            guard let version = EngineVersion(rest) else { return nil }
            terms.append(Term(op: op, version: version))
        }
        return EngineConstraint(terms: terms)
    }

    public func allows(_ version: EngineVersion) -> Bool {
        terms.allSatisfy { term in
            switch term.op {
            case ">=": return version >= term.version
            case "<=": return version <= term.version
            case ">": return version > term.version
            case "<": return version < term.version
            default: return version == term.version
            }
        }
    }
}

public enum WidgetTemplate {
    public static func resolve(_ template: String, inputs: [String: CatalogInput], values: [String: BoardScalar]) -> String {
        template.replacing(/\{\{\s*(inputs|context)\.([A-Za-z0-9_-]+)\s*\}\}/) { match in
            guard match.1 == "inputs" else { return "" }
            let key = String(match.2)
            return (values[key] ?? inputs[key]?.defaultValue)?.text ?? ""
        }
    }

    public static func arguments(of widget: CatalogWidget, values: [String: BoardScalar]) -> [String: String] {
        widget.source.with.mapValues { resolve($0, inputs: widget.inputs, values: values) }
    }
}

/// A widget that runs something itself instead of a provider of the app:
/// its source with templates filled, its view, and the `every` it really uses.
public struct ResolvedSource: Equatable, Sendable {
    public let source: WidgetSource
    public let view: WidgetView
    public let every: WidgetEvery
    public let needsApproval: Bool
    public let approvalHash: String?
    public let package: String?
    public let packagePath: String?

    public init(
        source: WidgetSource, view: WidgetView, every: WidgetEvery, needsApproval: Bool, approvalHash: String?,
        package: String?, packagePath: String?
    ) {
        self.source = source
        self.view = view
        self.every = every
        self.needsApproval = needsApproval
        self.approvalHash = approvalHash
        self.package = package
        self.packagePath = packagePath
    }
}

public struct ResolvedWidget: Equatable, Sendable {
    public let widget: CatalogWidget
    public let provider: String
    public let viewKind: String
    public let arguments: [String: String]
    public let every: TimeInterval
    public let minimum: CanvasSize
    public var source: ResolvedSource? = nil
    public var title: String? = nil
}

/// What a board entry becomes: something to draw, or a placeholder that
/// keeps its place, so a missing package never loses a layout.
public enum WidgetResolution: Equatable, Sendable {
    case ready(ResolvedWidget)
    case needsPackage(package: String, reason: String)
    case notFound(type: String)
    case needsNewerApp(type: String, reason: String)

    public static func resolve(
        _ instance: BoardWidget, in catalog: WidgetCatalog, contract: WidgetContract = .current
    ) -> WidgetResolution {
        if instance.isInline { return resolveInline(instance, contract: contract) }
        guard let widget = catalog.widget(named: instance.type) else { return .notFound(type: instance.type) }
        guard widget.available else { return .needsPackage(package: widget.package, reason: widget.unavailableReason) }
        let engine = EngineVersion(contract.engine) ?? EngineVersion(major: 1, minor: 0)
        if !widget.requiresEngine.isEmpty {
            guard let constraint = EngineConstraint.parse(widget.requiresEngine), constraint.allows(engine) else {
                return .needsNewerApp(
                    type: widget.name, reason: "it needs engine \(widget.requiresEngine); this app implements \(contract.engine)")
            }
        }
        if widget.source.kind != "provider" {
            return resolveSource(instance, widget: widget, contract: contract)
        }
        let provider = widget.source.name
        guard contract.sourceKinds.contains(widget.source.kind), let minimum = contract.minimumInterval(for: provider) else {
            return .needsNewerApp(type: widget.name, reason: "this app has no provider \(provider)")
        }
        guard contract.view(widget.viewKind, accepts: provider) else {
            return .needsNewerApp(type: widget.name, reason: "this app has no view \(widget.viewKind) for \(provider)")
        }
        let every = max(minimum, GoDuration.seconds(widget.source.every) ?? minimum)
        return .ready(ResolvedWidget(
            widget: widget, provider: provider, viewKind: widget.viewKind,
            arguments: WidgetTemplate.arguments(of: widget, values: instance.with), every: every,
            minimum: CanvasLayout.minimumSize(sizes: widget.sizes, contract: contract)))
    }

    private static func resolveSource(
        _ instance: BoardWidget, widget: CatalogWidget, contract: WidgetContract
    ) -> WidgetResolution {
        let scope = WidgetScope.package(inputs: Set(widget.inputs.keys), contextKeys: Set(widget.context.keys))
        let source: WidgetSource
        let view: WidgetView
        do {
            source = try WidgetSourceReader.read(raisingEvery(of: widget.source.raw, contract: contract), scope: scope, contract: contract)
            view = try WidgetViewReader.read(
                widget.view, source: source, sourceWritesParse: widget.source.raw["parse"] != nil, scope: scope,
                contract: contract)
        } catch let problem as WidgetSpecProblem {
            return .needsNewerApp(type: widget.name, reason: problem.message)
        } catch {
            return .needsNewerApp(type: widget.name, reason: "\(error)")
        }
        let inputs = widget.inputs.compactMapValues { $0.defaultValue?.text }
            .merging(instance.with.mapValues(\.text)) { _, chosen in chosen }
        let resolved = source.resolved(with: TemplateValues(inputs: inputs, context: [:]))
        let every = floored(resolved.every, kind: resolved.kind, contract: contract)
        return .ready(ResolvedWidget(
            widget: widget, provider: "", viewKind: view.kind, arguments: [:], every: every.seconds ?? 0,
            minimum: CanvasLayout.minimumSize(sizes: widget.sizes, contract: contract),
            source: ResolvedSource(
                source: resolved, view: view, every: every, needsApproval: false, approvalHash: nil,
                package: widget.package, packagePath: widget.packagePath)))
    }

    /// A widget written in a board resolves without the catalog: it carries
    /// its own source and view, already checked by the board reader.
    public static func resolveInline(_ instance: BoardWidget, contract: WidgetContract = .current) -> WidgetResolution {
        guard let inline = instance.inline else { return .notFound(type: instance.type) }
        let widget = CatalogWidget.inline(
            id: instance.id, title: inline.title, sizes: inline.sizes, fits: inline.fits, viewKind: inline.view.kind)
        let minimum = CanvasLayout.minimumSize(sizes: widget.sizes, contract: contract)
        if case let .provider(provider) = inline.source {
            guard let floor = contract.minimumInterval(for: provider.name),
                  contract.view(inline.view.kind, accepts: provider.name)
            else { return .needsNewerApp(type: instance.id, reason: "this app has no provider \(provider.name)") }
            return .ready(ResolvedWidget(
                widget: widget, provider: provider.name, viewKind: inline.view.kind, arguments: provider.with,
                every: max(floor, GoDuration.seconds(provider.every) ?? floor), minimum: minimum, title: inline.title))
        }
        let source = inline.source.resolved(with: .none)
        let needsApproval = contract.needsApproval(source.kind)
        let every = floored(source.every, kind: source.kind, contract: contract)
        return .ready(ResolvedWidget(
            widget: widget, provider: "", viewKind: inline.view.kind, arguments: [:], every: every.seconds ?? 0,
            minimum: minimum,
            source: ResolvedSource(
                source: source, view: inline.view, every: every, needsApproval: needsApproval,
                approvalHash: needsApproval ? ApprovalSubject.hash(source) : nil, package: nil, packagePath: nil),
            title: inline.title))
    }

    /// The CLI refused a catalog widget under the minimum, so a lower value
    /// here comes from an older contract and is raised rather than refused.
    private static func raisingEvery(of raw: WidgetValue, contract: WidgetContract) -> WidgetValue {
        guard var fields = raw.object, let kind = fields["kind"]?.string, let text = fields["every"]?.string,
              let seconds = GoDuration.seconds(text), let floor = contract.minimumInterval(forSource: kind),
              let floorText = contract.sources[kind]?.minEvery, seconds < floor
        else { return raw }
        fields["every"] = .string(floorText)
        return .object(fields)
    }

    private static func floored(_ every: WidgetEvery, kind: String, contract: WidgetContract) -> WidgetEvery {
        guard case let .interval(seconds) = every, let floor = contract.minimumInterval(forSource: kind) else { return every }
        return .interval(max(floor, seconds))
    }
}

public enum WidgetResolutionCopy {
    public static func title(_ resolution: WidgetResolution) -> String {
        switch resolution {
        case let .ready(resolved): return resolved.title ?? WidgetTitle.make(type: resolved.widget.name)
        case let .needsPackage(package, _): return "Needs the \(package) package"
        case .notFound: return "Widget not found"
        case .needsNewerApp: return "Needs a newer app"
        }
    }

    public static func detail(_ resolution: WidgetResolution, release: String) -> String {
        switch resolution {
        case .ready: return ""
        case let .needsPackage(package, reason):
            return reason.isEmpty ? "Add the \(package) package to a machine, then sync." : reason
        case let .notFound(type):
            return "\(type) is not in packages release \(release) or in your own packages folder."
        case let .needsNewerApp(_, reason):
            return "This app cannot draw it: \(reason)."
        }
    }
}

public enum WidgetTitle {
    private static let acronyms = ["api": "API", "cli": "CLI", "pr": "PR", "prs": "PRs"]

    public static func make(type: String) -> String {
        phrase(widgetPart(type), capitalizesFirst: true)
    }

    /// Two widgets with the same name from different packages ("usage")
    /// would read the same, so each takes its package's name in front.
    public static func make(type: String, in catalog: WidgetCatalog?) -> String {
        let widget = widgetPart(type)
        let package = type.split(separator: "/", maxSplits: 1).first.map(String.init) ?? type
        guard let catalog, catalog.widgets.contains(where: { $0.widget == widget && $0.package != package }) else {
            return make(type: type)
        }
        return displayName(package: package) + " " + phrase(widget, capitalizesFirst: false)
    }

    public static func displayName(package: String) -> String {
        words(package).map { word($0, capitalized: true) }.joined(separator: " ")
    }

    private static func widgetPart(_ type: String) -> String {
        type.split(separator: "/").last.map(String.init) ?? type
    }

    private static func phrase(_ name: String, capitalizesFirst: Bool) -> String {
        words(name).enumerated()
            .map { word($0.element, capitalized: capitalizesFirst && $0.offset == 0) }
            .joined(separator: " ")
    }

    private static func words(_ name: String) -> [String] {
        name.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
    }

    private static func word(_ word: String, capitalized: Bool) -> String {
        if let acronym = acronyms[word.lowercased()] { return acronym }
        return capitalized ? word.prefix(1).uppercased() + word.dropFirst() : word
    }
}

public enum WidgetGallery {
    /// What the "+" gallery lists for a surface: usable ones first, then by name.
    public static func entries(_ catalog: WidgetCatalog, surface: String) -> [CatalogWidget] {
        catalog.widgets
            .filter { $0.surfaces.contains(surface) }
            .sorted { ($0.available ? 0 : 1, $0.name) < ($1.available ? 0 : 1, $1.name) }
    }

    public struct UnavailableHint: Equatable, Sendable {
        public let advice: String
        public let command: String?

        public init(advice: String, command: String?) {
            self.advice = advice
            self.command = command
        }
    }

    /// The CLI writes `unavailable_reason` as "advice: devmachine …"; the
    /// command part is offered on its own so it can be copied and run.
    public static func hint(_ reason: String) -> UnavailableHint {
        guard let range = reason.range(of: ": devmachine ") else { return UnavailableHint(advice: reason, command: nil) }
        let command = String(reason[reason.index(range.lowerBound, offsetBy: 2)...])
        return UnavailableHint(advice: String(reason[..<range.lowerBound]), command: command)
    }
}
