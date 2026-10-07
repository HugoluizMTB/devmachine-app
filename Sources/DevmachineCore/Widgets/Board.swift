import CoreGraphics
import Foundation

/// One input value of a board entry. YAML has more types, but an input is
/// text, a number or a switch.
public enum BoardScalar: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public var text: String {
        switch self {
        case let .string(value): return value
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        }
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

public struct BoardWidget: Equatable, Sendable, Identifiable {
    public static let customSize = "custom"

    public var id: String
    public var type: String
    public var with: [String: BoardScalar]
    public var frame: BoardFrame
    public var size: String
    public var minimized: Bool
    public var z: Int

    public init(
        id: String, type: String, with: [String: BoardScalar] = [:], frame: BoardFrame, size: String,
        minimized: Bool = false, z: Int
    ) {
        self.id = id
        self.type = type
        self.with = with
        self.frame = frame
        self.size = size
        self.minimized = minimized
        self.z = z
    }

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
        let cleaned = base.lowercased()
            .map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" || result.isEmpty { return }
                result.append(character)
            }
        var stem = cleaned
        while stem.hasSuffix("-") { stem.removeLast() }
        if stem.isEmpty { stem = "widget" }
        let taken = Set(widgets.map(\.id))
        guard taken.contains(stem) else { return stem }
        var counter = 2
        while taken.contains("\(stem)-\(counter)") { counter += 1 }
        return "\(stem)-\(counter)"
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
