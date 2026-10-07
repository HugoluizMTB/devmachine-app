import Foundation

/// `{{json.<path>}}`: which part of a JSON answer a view shows. A path is
/// dot-separated keys or list positions (`items.0.name`), as the CLI checks it.
public enum JSONPath {
    static var template: Regex<(Substring, Substring)> {
        /\{\{\s*json\.([A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)*)\s*\}\}/
    }

    public static func isTemplate(_ text: String) -> Bool {
        path(of: text) != nil
    }

    public static func path(of text: String) -> String? {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: template).map { String($0.1) }
    }

    public static func value(_ path: String, in root: WidgetValue) -> WidgetValue? {
        var current = root
        for part in path.split(separator: ".", omittingEmptySubsequences: false).map(String.init) {
            switch current {
            case let .object(fields):
                guard let next = fields[part] else { return nil }
                current = next
            case let .list(items):
                guard let index = Int(part), items.indices.contains(index) else { return nil }
                current = items[index]
            default:
                return nil
            }
        }
        return current
    }

    /// A `view.value` that is one template keeps the JSON value's type, so a
    /// number view gets a number; text around templates makes it a string.
    /// Nil when a path is not in the answer.
    public static func resolve(_ text: String, in root: WidgetValue) -> WidgetValue? {
        if let path = path(of: text) {
            return value(path, in: root)
        }
        var result = ""
        var rest = text[...]
        for match in text.matches(of: template) {
            guard let found = value(String(match.1), in: root) else { return nil }
            result += rest[rest.startIndex..<match.range.lowerBound] + found.text
            rest = text[match.range.upperBound...]
        }
        return .string(result + rest)
    }

    /// The CLI validator's message for a `view.value` it refuses, or nil.
    public static func problem(in value: String) -> String? {
        let matches = value.matches(of: WidgetSourceReader.templatePattern)
        if matches.isEmpty {
            return "view.value \"\(value)\" names no field: write it like \"{{json.used}}\""
        }
        for match in matches where match.0.wholeMatch(of: template) == nil {
            return "template \(match.0) in view.value names json.<path>, like {{json.disk.used}}"
        }
        return nil
    }
}

public enum SourceOutput: Hashable, Sendable {
    case text(String)
    case lines([String])
    case number(Double)
    case json(WidgetValue)
    case ansi(String)
    case status(code: Int, latency: TimeInterval)
}

public struct OutputParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Turns what a command, a URL or a harness printed into what a view draws.
/// A failure is an error for the widget, which keeps its last good value.
public enum OutputParser {
    public static let maxBytes = 1_048_576

    public static func parse(_ data: Data, as mode: ParseMode) throws -> SourceOutput {
        guard data.count <= maxBytes else {
            throw OutputParseError(message: "printed more than 1 MB")
        }
        let text = String(decoding: data, as: UTF8.self)
        switch mode {
        case .text: return .text(trimmingTrailingNewlines(text))
        case .ansi: return .ansi(trimmingTrailingNewlines(text))
        case .lines:
            var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.last == "" { lines.removeLast() }
            return .lines(lines)
        case .number:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed), value.isFinite else {
                throw OutputParseError(message: "expected a number, got \"\(String(trimmed.prefix(40)))\"")
            }
            return .number(value)
        case .json:
            do {
                return .json(try JSONDecoder().decode(WidgetValue.self, from: data))
            } catch {
                throw OutputParseError(message: "not valid JSON: \(String(text.prefix(80)))")
            }
        case .status:
            throw OutputParseError(message: "a status comes from a web address, not from output")
        }
    }

    private static func trimmingTrailingNewlines(_ text: String) -> String {
        var result = Substring(text)
        while let last = result.last, last == "\n" || last == "\r" || last == "\r\n" { result.removeLast() }
        return String(result)
    }
}
