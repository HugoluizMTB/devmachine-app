import Foundation

/// A value of a widget's source or view as JSON (the catalog) or YAML (a
/// board) holds it, so one reader serves both.
public indirect enum WidgetValue: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case list([WidgetValue])
    case object([String: WidgetValue])
    case null

    public var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var number: Double? {
        switch self {
        case let .int(value): return Double(value)
        case let .double(value): return value
        case let .string(value): return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    public var bool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var list: [WidgetValue]? {
        if case let .list(value) = self { return value }
        return nil
    }

    public var object: [String: WidgetValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public subscript(key: String) -> WidgetValue? { object?[key] }

    public var text: String {
        switch self {
        case let .string(value): return value
        case let .int(value): return String(value)
        case let .double(value): return GoFloat.json(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return ""
        case .list, .object: return canonicalJSON
        }
    }

    /// Keys sorted by their UTF-8 bytes and no whitespace, so equal values
    /// always give equal text (the approval hash depends on it).
    public var canonicalJSON: String {
        switch self {
        case let .string(value): return Self.quoted(value)
        case let .int(value): return String(value)
        case let .double(value):
            if value.isFinite, value.rounded() == value, abs(value) < 1e15 { return String(Int(value)) }
            return value.isFinite ? String(value) : "null"
        case let .bool(value): return value ? "true" : "false"
        case .null: return "null"
        case let .list(items): return "[" + items.map(\.canonicalJSON).joined(separator: ",") + "]"
        case let .object(fields):
            let keys = fields.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            return "{" + keys.map { Self.quoted($0) + ":" + (fields[$0] ?? .null).canonicalJSON }
                .joined(separator: ",") + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

extension WidgetValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WidgetValue].self) {
            self = .list(value)
        } else {
            self = .object(try container.decode([String: WidgetValue].self))
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
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
