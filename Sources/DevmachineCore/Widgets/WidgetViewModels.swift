import Foundation

/// Small and medium presets show the short form of a view; only a frame at
/// least 240 points on its smaller side has room for the full one.
public enum WidgetDensity: Equatable, Sendable {
    case compact, full

    public static let fullMinimum: Double = 240

    public static func of(width: Double, height: Double) -> WidgetDensity {
        min(width, height) >= fullMinimum ? .full : .compact
    }
}

/// Explicit formatting with the POSIX locale, so a number never reads as
/// `5.182` in a pt-BR system (CLAUDE.md, "Numbers shown to the user").
public enum NumberText {
    public static func format(_ value: Double, format: NumberFormat, unit: String?) -> String {
        let body: String
        switch format {
        case .plain: body = plain(value)
        case .percent: return plain(value) + "%"
        case .bytes: return bytes(value)
        case .duration: return duration(value)
        }
        guard let unit, !unit.isEmpty else { return body }
        return body + " " + unit
    }

    static func plain(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var amount = value
        var index = 0
        while abs(amount) >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return plain((amount * 10).rounded() / 10) + " " + units[index]
    }

    private static func duration(_ value: Double) -> String {
        let total = Int(value.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

public struct ValueError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

public enum ValueExtraction {
    public static func value(from output: SourceOutput, view: WidgetView) throws -> WidgetValue {
        switch output {
        case let .number(number): return .double(number)
        case let .status(code, _): return .int(code)
        case let .text(text), let .ansi(text): return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case let .lines(lines): return .string(lines.joined(separator: "\n"))
        case let .json(root):
            guard let template = view.value else { return root }
            guard let found = JSONPath.resolve(template, in: root) else {
                throw ValueError(message: "\(template) found nothing in the answer")
            }
            return found
        }
    }

    public static func number(from output: SourceOutput, view: WidgetView) throws -> Double {
        let found = try value(from: output, view: view)
        guard case .bool = found else {
            if let number = found.number, number.isFinite { return number }
            throw ValueError(message: "\(view.value ?? "the output") is \"\(String(found.text.prefix(40)))\", not a number")
        }
        throw ValueError(message: "\(view.value ?? "the output") is \(found.text), not a number")
    }
}

public enum WidgetLevel: Equatable, Sendable {
    case ok, warn, bad, neutral
}

public struct GaugeModel: Equatable, Sendable {
    public let fraction: Double
    public let level: WidgetLevel
    public let label: String

    public init(fraction: Double, level: WidgetLevel, label: String) {
        self.fraction = fraction
        self.level = level
        self.label = label
    }

    public init(value: Double, view: WidgetView) {
        let top = view.max ?? 100
        let span = top - view.min
        fraction = span > 0 ? Swift.min(1, Swift.max(0, (value - view.min) / span)) : 0
        if let crit = view.crit, value >= crit {
            level = .bad
        } else if let warn = view.warn, value >= warn {
            level = .warn
        } else {
            level = .ok
        }
        label = NumberText.format(value, format: view.format, unit: view.unit)
    }
}

public struct StatusModel: Equatable, Sendable {
    public let level: WidgetLevel
    public let label: String

    public init(level: WidgetLevel, label: String) {
        self.level = level
        self.label = label
    }

    /// A URL with no rules is ok below 400. Other output with no rules is
    /// shown as it is, neither good nor bad.
    public static func make(output: SourceOutput, view: WidgetView) throws -> StatusModel {
        let value = try ValueExtraction.value(from: output, view: view)
        let number = value.number
        let text = value.text
        let label: String
        if case let .status(code, latency) = output {
            label = "\(code) · \(Int((latency * 1000).rounded())) ms"
        } else {
            label = number.map { NumberText.plain($0) } ?? text
        }
        if view.okRule == nil, view.warnRule == nil {
            if case let .status(code, _) = output { return StatusModel(level: code < 400 ? .ok : .bad, label: label) }
            return StatusModel(level: .neutral, label: label)
        }
        if view.okRule?.matches(number: number, text: text) == true { return StatusModel(level: .ok, label: label) }
        if view.warnRule?.matches(number: number, text: text) == true { return StatusModel(level: .warn, label: label) }
        return StatusModel(level: .bad, label: label)
    }
}

public struct ListItem: Equatable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let subtitle: String?
    public let status: String?
    public let link: URL?

    public init(id: Int, title: String, subtitle: String?, status: String?, link: URL?) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.link = link
    }
}

public enum ListModel {
    public static func items(output: SourceOutput, template: ListItemTemplate) throws -> [ListItem] {
        let elements: [WidgetValue]
        switch output {
        case let .lines(lines): elements = lines.map(WidgetValue.string)
        case let .json(.list(items)): elements = items
        case .json: throw ValueError(message: "a list view needs a JSON array")
        default: throw ValueError(message: "a list view needs lines or a JSON array")
        }
        return elements.enumerated().map { index, element in
            func fill(_ text: String?) -> String? {
                text.map { value in
                    value.replacing(/\{\{\s*item(?:\.([A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)*))?\s*\}\}/) { match in
                        guard let path = match.1 else { return element.text }
                        return JSONPath.value(String(path), in: element)?.text ?? ""
                    }
                }
            }
            let link = fill(template.link).flatMap(URL.init(string:)).flatMap { PreviewURLPolicy.isWeb($0) ? $0 : nil }
            return ListItem(
                id: index, title: fill(template.title) ?? "", subtitle: fill(template.subtitle).flatMap { $0.isEmpty ? nil : $0 },
                status: fill(template.status).flatMap { $0.isEmpty ? nil : $0 }, link: link)
        }
    }
}

public enum TextTail {
    public static func lines(of text: String, tail: Int?) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let tail, lines.count > tail else { return lines }
        return Array(lines.suffix(tail))
    }
}
