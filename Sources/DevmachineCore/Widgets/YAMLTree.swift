import Foundation
import Yams

/// One `key: value` of a mapping in a `YAMLTree`, kept in the order it was written.
public struct YAMLPair: Equatable, Sendable {
    public let key: String
    public let value: YAMLTree

    public init(key: String, value: YAMLTree) {
        self.key = key
        self.value = value
    }
}

/// An inline widget's `source` and `view` as they were written, styles
/// included, so the app writes them back the way the CLI's `yaml.v3` does:
/// unchanged. Lines are kept for problems and ignored by `==`.
public indirect enum YAMLTree: Sendable {
    public enum ScalarStyle: Equatable, Sendable {
        case plain, singleQuoted, doubleQuoted, block
    }

    case scalar(String, ScalarStyle, line: Int?)
    case mapping([YAMLPair], flow: Bool, line: Int?)
    case sequence([YAMLTree], flow: Bool, line: Int?)

    /// The text a board was composed from, cut into lines where libyaml
    /// cuts them, so a node's mark finds its own line in a CRLF file too.
    public struct SourceLines: Sendable {
        let lines: [[Unicode.Scalar]]

        public init(_ text: String) {
            var lines: [[Unicode.Scalar]] = []
            var current: [Unicode.Scalar] = []
            var afterCR = false
            for scalar in text.unicodeScalars {
                if afterCR, scalar == "\n" {
                    afterCR = false
                    continue
                }
                afterCR = scalar == "\r"
                if YAMLScalarStyle.isBreak(scalar) {
                    lines.append(current)
                    current = []
                } else {
                    current.append(scalar)
                }
            }
            lines.append(current)
            self.lines = lines
        }

        func firstCharacter(at mark: Mark?) -> Unicode.Scalar? {
            guard let mark, lines.indices.contains(mark.line - 1) else { return nil }
            var rest = lines[mark.line - 1].dropFirst(mark.column - 1)
            if rest.first == "!" {
                rest = rest.drop { $0 != " " && $0 != "\t" }.drop { $0 == " " || $0 == "\t" }
            }
            return rest.first
        }
    }

    /// `text` is the YAML `node` was composed from. Yams 5.4 reads a
    /// collection's style from its end event, so every collection comes back
    /// block; and it hands an alias back as the anchored node itself. Both
    /// are seen in the text at the node's mark instead.
    public init(node: Node, text: String) throws {
        try self.init(node: node, lines: SourceLines(text))
    }

    public init(node: Node, lines: SourceLines) throws {
        let opening = lines.firstCharacter(at: node.mark)
        if opening == "&" || opening == "*" {
            throw Self.aliasProblem(node)
        }
        switch node {
        case let .scalar(scalar):
            let style: ScalarStyle
            switch scalar.style {
            case .singleQuoted: style = .singleQuoted
            case .doubleQuoted: style = .doubleQuoted
            case .literal, .folded: style = .block
            default: style = .plain
            }
            self = .scalar(scalar.string, style, line: node.mark?.line)
        case let .mapping(mapping):
            var pairs: [YAMLPair] = []
            var seen: Set<String> = []
            for (key, value) in mapping {
                guard let name = key.scalar?.string else {
                    throw BoardProblem(line: key.mark?.line, message: "a key inside a widget's source or view is not text")
                }
                if let opening = lines.firstCharacter(at: key.mark), opening == "&" || opening == "*" {
                    throw Self.aliasProblem(key)
                }
                guard seen.insert(name).inserted else {
                    throw BoardProblem(line: key.mark?.line, message: "\"\(name)\" appears twice")
                }
                pairs.append(YAMLPair(key: name, value: try YAMLTree(node: value, lines: lines)))
            }
            self = .mapping(pairs, flow: opening == "{", line: node.mark?.line)
        case let .sequence(sequence):
            let items = try sequence.map { try YAMLTree(node: $0, lines: lines) }
            self = .sequence(items, flow: opening == "[", line: node.mark?.line)
        case .alias:
            throw Self.aliasProblem(node)
        }
    }

    private static func aliasProblem(_ node: Node) -> BoardProblem {
        BoardProblem(line: node.mark?.line, message: "anchors and aliases are not read inside a widget's source or view")
    }

    public var line: Int? {
        switch self {
        case let .scalar(_, _, line), let .mapping(_, _, line), let .sequence(_, _, line): return line
        }
    }

    public var value: WidgetValue {
        switch self {
        case let .scalar(text, style, _):
            return style == .plain ? YAMLPlainScalar.value(text) : .string(text)
        case let .mapping(pairs, _, _):
            return .object(Dictionary(pairs.map { ($0.key, $0.value.value) }, uniquingKeysWith: { _, last in last }))
        case let .sequence(items, _, _):
            return .list(items.map(\.value))
        }
    }

    public func line(at path: [String]) -> Int? {
        guard let first = path.first else { return line }
        switch self {
        case let .mapping(pairs, _, _):
            return pairs.first { $0.key == first }?.value.line(at: Array(path.dropFirst()))
        case let .sequence(items, _, _):
            guard let index = Int(first), items.indices.contains(index) else { return nil }
            return items[index].line(at: Array(path.dropFirst()))
        case .scalar:
            return nil
        }
    }

    /// `key: value` at `indent` spaces, block collections on the lines after,
    /// two more spaces in, sequences as `- item` (yaml.v3's layout).
    public func emit(key: String, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let name = YAMLScalarStyle.text(key, in: .block)
        switch self {
        case .scalar, .mapping(_, true, _), .sequence(_, true, _):
            return ["\(pad)\(name): \(flow)"]
        case let .mapping(pairs, _, _):
            guard !pairs.isEmpty else { return ["\(pad)\(name): {}"] }
            return ["\(pad)\(name):"] + pairs.flatMap { $0.value.emit(key: $0.key, indent: indent + 2) }
        case let .sequence(items, _, _):
            guard !items.isEmpty else { return ["\(pad)\(name): []"] }
            return ["\(pad)\(name):"] + items.flatMap { $0.emitItem(indent: indent + 2) }
        }
    }

    private func emitItem(indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let nested: [String]
        switch self {
        case let .mapping(pairs, false, _) where !pairs.isEmpty:
            nested = pairs.flatMap { $0.value.emit(key: $0.key, indent: indent + 2) }
        case let .sequence(items, false, _) where !items.isEmpty:
            nested = items.flatMap { $0.emitItem(indent: indent + 2) }
        default:
            return ["\(pad)- \(flow)"]
        }
        return ["\(pad)- " + nested[0].dropFirst(indent + 2)] + nested.dropFirst()
    }

    private var flow: String {
        switch self {
        case let .scalar(text, style, _):
            switch style {
            case .plain:
                return text.unicodeScalars.contains(where: YAMLScalarStyle.isBreak) ? YAMLScalarStyle.doubleQuoted(text) : text
            case .singleQuoted: return YAMLScalarStyle.singleQuotedIfAllowed(text)
            case .doubleQuoted, .block: return YAMLScalarStyle.doubleQuoted(text)
            }
        case let .mapping(pairs, _, _):
            return "{" + pairs.map { YAMLScalarStyle.text($0.key, in: .flow) + ": " + $0.value.flow }.joined(separator: ", ") + "}"
        case let .sequence(items, _, _):
            return "[" + items.map(\.flow).joined(separator: ", ") + "]"
        }
    }
}

extension YAMLTree: Equatable {
    public static func == (lhs: YAMLTree, rhs: YAMLTree) -> Bool {
        switch (lhs, rhs) {
        case let (.scalar(a, styleA, _), .scalar(b, styleB, _)): return a == b && styleA == styleB
        case let (.mapping(a, flowA, _), .mapping(b, flowB, _)): return a == b && flowA == flowB
        case let (.sequence(a, flowA, _), .sequence(b, flowB, _)): return a == b && flowA == flowB
        default: return false
        }
    }
}

/// Types a plain scalar the way go-yaml v3 resolves it, so a value the CLI
/// reads as a switch or a number reads the same here (`True`, `0x10`, `1_000`).
enum YAMLPlainScalar {
    private static let words: [String: WidgetValue] = [
        "true": .bool(true), "True": .bool(true), "TRUE": .bool(true),
        "false": .bool(false), "False": .bool(false), "FALSE": .bool(false),
        "": .null, "~": .null, "null": .null, "Null": .null, "NULL": .null,
        ".nan": .double(.nan), ".NaN": .double(.nan), ".NAN": .double(.nan),
        ".inf": .double(.infinity), ".Inf": .double(.infinity), ".INF": .double(.infinity),
        "+.inf": .double(.infinity), "+.Inf": .double(.infinity), "+.INF": .double(.infinity),
        "-.inf": .double(-.infinity), "-.Inf": .double(-.infinity), "-.INF": .double(-.infinity),
    ]

    static func value(_ text: String) -> WidgetValue {
        if let word = words[text] { return word }
        guard let first = text.first, first == "." || first == "+" || first == "-" || first.isASCII && first.isNumber else {
            return .string(text)
        }
        let plain = first == "." ? text : text.replacingOccurrences(of: "_", with: "")
        if first != ".", let number = integer(plain) { return .int(number) }
        if plain.wholeMatch(of: /[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?/) != nil, let number = Double(plain) {
            return .double(number)
        }
        return .string(text)
    }

    /// Go's `strconv.ParseInt(text, 0, 64)`: a sign, then `0x`, `0o`, `0b`,
    /// a leading `0` for octal, or decimal.
    private static func integer(_ text: String) -> Int? {
        var rest = Substring(text)
        var negative = false
        if let sign = rest.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            rest = rest.dropFirst()
        }
        var radix = 10
        let lowered = rest.lowercased()
        if lowered.hasPrefix("0x") {
            radix = 16
            rest = rest.dropFirst(2)
        } else if lowered.hasPrefix("0o") {
            radix = 8
            rest = rest.dropFirst(2)
        } else if lowered.hasPrefix("0b") {
            radix = 2
            rest = rest.dropFirst(2)
        } else if rest.count > 1, rest.first == "0" {
            radix = 8
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty, rest.allSatisfy({ $0.isASCII && $0.isHexDigit }), let magnitude = UInt64(rest, radix: radix) else {
            return nil
        }
        let limit = UInt64(Int64.max)
        if negative {
            guard magnitude <= limit + 1 else { return nil }
            return magnitude == limit + 1 ? Int.min : -Int(magnitude)
        }
        return magnitude <= limit ? Int(magnitude) : nil
    }
}
