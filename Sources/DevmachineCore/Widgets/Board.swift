import CoreGraphics
import Foundation

/// One input value of a board entry. YAML has more types, but an input is
/// text, a number or a switch.
public enum BoardScalar: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    /// Only for a `many` choice input; a template reads it joined with commas.
    case list([String])

    public var text: String {
        switch self {
        case let .string(value): return value
        case let .int(value): return String(value)
        case let .double(value): return GoFloat.json(value)
        case let .bool(value): return value ? "true" : "false"
        case let .list(values): return values.joined(separator: ",")
        }
    }

    public var listValue: [String]? {
        if case let .list(values) = self { return values }
        return nil
    }
}

extension BoardScalar: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode([String].self) {
            self = .list(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .list(value): try container.encode(value)
        }
    }
}

/// A widget's place on a canvas, in points at 100% text size.
public struct BoardFrame: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var rect: CGRect { CGRect(x: Double(x), y: Double(y), width: Double(w), height: Double(h)) }
}

/// A widget written straight into a board: its own source and view, no
/// package. The trees are what gets written back.
public struct InlineWidget: Equatable, Sendable {
    public var title: String
    public var sourceTree: YAMLTree
    public var viewTree: YAMLTree
    public var sizes: [String]
    public var fits: [String]
    public var source: WidgetSource
    public var view: WidgetView

    public init(
        title: String, sourceTree: YAMLTree, viewTree: YAMLTree, sizes: [String], fits: [String],
        source: WidgetSource, view: WidgetView
    ) {
        self.title = title
        self.sourceTree = sourceTree
        self.viewTree = viewTree
        self.sizes = sizes
        self.fits = fits
        self.source = source
        self.view = view
    }
}

public struct BoardWidget: Equatable, Sendable, Identifiable {
    public static let customSize = "custom"

    public var id: String
    public var type: String
    public var with: [String: BoardScalar]
    public var frame: BoardFrame
    public var size: String
    public var minimized: Bool
    public var z: Int
    public var inline: InlineWidget?
    public var titleOverride: String?
    public var everyOverride: String?

    public init(
        id: String, type: String, with: [String: BoardScalar] = [:], frame: BoardFrame, size: String,
        minimized: Bool = false, z: Int, inline: InlineWidget? = nil, titleOverride: String? = nil,
        everyOverride: String? = nil
    ) {
        self.id = id
        self.type = type
        self.with = with
        self.frame = frame
        self.size = size
        self.minimized = minimized
        self.z = z
        self.inline = inline
        self.titleOverride = titleOverride
        self.everyOverride = everyOverride
    }

    public var isInline: Bool { inline != nil }

    public var package: String { String(type.split(separator: "/").first ?? "") }
}

public struct Board: Equatable, Sendable {
    public static let format = 1

    public var surface: String
    public var widgets: [BoardWidget]

    public init(surface: String, widgets: [BoardWidget]) {
        self.surface = surface
        self.widgets = widgets
    }

    public var topZ: Int { widgets.map(\.z).max() ?? 0 }

    public func uniqueID(base: String) -> String {
        BoardIDs.unique(base: base, taken: Set(widgets.map(\.id)))
    }
}

/// What is wrong with a board file, and where, for the banner.
public struct BoardProblem: Error, Equatable, Sendable, CustomStringConvertible {
    public let line: Int?
    public let message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String { line.map { "line \($0): \(message)" } ?? message }
}

/// The id rule every board shares: lower case a-z, 0-9 and single dashes,
/// numbered from 2 when taken.
public enum BoardIDs {
    public static func unique(base: String, taken: Set<String>) -> String {
        let cleaned = base.lowercased()
            .map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" || result.isEmpty { return }
                result.append(character)
            }
        var stem = cleaned
        while stem.hasSuffix("-") { stem.removeLast() }
        if stem.isEmpty { stem = "widget" }
        guard taken.contains(stem) else { return stem }
        var counter = 2
        while taken.contains("\(stem)-\(counter)") { counter += 1 }
        return "\(stem)-\(counter)"
    }
}
