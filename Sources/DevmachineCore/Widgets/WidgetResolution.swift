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

public struct ResolvedWidget: Equatable, Sendable {
    public let widget: CatalogWidget
    public let provider: String
    public let viewKind: String
    public let arguments: [String: String]
    public let every: TimeInterval
    public let minimum: CanvasSize
}

/// What a board entry becomes: something to draw, or a placeholder that
/// keeps its place, so a missing package never loses a layout.
public enum WidgetResolution: Equatable, Sendable {
    case ready(ResolvedWidget)
    case needsPackage(package: String, reason: String)
    case notFound(type: String)
    case needsNewerApp(type: String, reason: String)

    public static func resolve(
        _ instance: BoardWidget, in catalog: WidgetCatalog, contract: WidgetContract = .engine10
    ) -> WidgetResolution {
        guard let widget = catalog.widget(named: instance.type) else { return .notFound(type: instance.type) }
        guard widget.available else { return .needsPackage(package: widget.package, reason: widget.unavailableReason) }
        let engine = EngineVersion(contract.engine) ?? EngineVersion(major: 1, minor: 0)
        if !widget.requiresEngine.isEmpty {
            guard let constraint = EngineConstraint.parse(widget.requiresEngine), constraint.allows(engine) else {
                return .needsNewerApp(
                    type: widget.name, reason: "it needs engine \(widget.requiresEngine); this app implements \(contract.engine)")
            }
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
}

public enum WidgetResolutionCopy {
    public static func title(_ resolution: WidgetResolution) -> String {
        switch resolution {
        case let .ready(resolved): return WidgetTitle.make(type: resolved.widget.name)
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
    public static func make(type: String) -> String {
        let part = type.split(separator: "/").last.map(String.init) ?? type
        let words = part.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
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
