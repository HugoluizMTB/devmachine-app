import Foundation

public enum NumberFormat: String, Hashable, Sendable {
    case plain, percent, bytes, duration
}

/// `< 300`, `== "ok"`: what makes a status ok or a warning.
public struct StatusRule: Hashable, Sendable {
    public enum Op: String, Hashable, Sendable { case lt = "<", le = "<=", gt = ">", ge = ">=", eq = "==", ne = "!=" }
    public enum Operand: Hashable, Sendable {
        case number(Double)
        case text(String)
    }

    public let op: Op
    public let operand: Operand

    public init(op: Op, operand: Operand) {
        self.op = op
        self.operand = operand
    }

    public static func parse(_ text: String) -> StatusRule? {
        guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(<=|>=|==|!=|<|>)\s*(.+)/),
              let op = Op(rawValue: String(match.1))
        else { return nil }
        let rest = String(match.2).trimmingCharacters(in: .whitespaces)
        if rest.count >= 2, rest.hasPrefix("\""), rest.hasSuffix("\"") {
            guard op == .eq || op == .ne else { return nil }
            return StatusRule(op: op, operand: .text(String(rest.dropFirst().dropLast())))
        }
        guard rest.wholeMatch(of: /-?\d+(?:\.\d+)?/) != nil, let number = Double(rest) else { return nil }
        return StatusRule(op: op, operand: .number(number))
    }

    public var comparesBySize: Bool { op != .eq && op != .ne }

    public func matches(number: Double?, text: String) -> Bool {
        switch operand {
        case let .text(expected):
            return op == .eq ? text == expected : text != expected
        case let .number(expected):
            guard let number else { return false }
            switch op {
            case .lt: return number < expected
            case .le: return number <= expected
            case .gt: return number > expected
            case .ge: return number >= expected
            case .eq: return number == expected
            case .ne: return number != expected
            }
        }
    }
}

public struct ListItemTemplate: Hashable, Sendable {
    public var title: String
    public var subtitle: String?
    public var status: String?
    public var link: String?

    public init(title: String = "{{item}}", subtitle: String? = nil, status: String? = nil, link: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.link = link
    }
}

public struct WidgetView: Hashable, Sendable {
    public var kind: String
    public var wrap = true
    public var tail: Int?
    public var value: String?
    public var unit: String?
    public var format = NumberFormat.plain
    public var min: Double = 0
    public var max: Double?
    public var warn: Double?
    public var crit: Double?
    public var okRule: StatusRule?
    public var warnRule: StatusRule?
    public var item = ListItemTemplate()
    public var zoom: Double = 1

    public init(kind: String) {
        self.kind = kind
        if kind == "gauge" { max = 100 }
    }
}

/// Reads a view with the contract's accept table and the rules the CLI
/// also applies.
public enum WidgetViewReader {
    private static let valueKinds: Set<String> = ["number", "gauge", "status", "sparkline"]
    private static var itemPattern: Regex<(Substring, Substring?)> { /\{\{\s*item(?:\.([A-Za-z0-9_.\[\]-]+))?\s*\}\}/ }

    public static func read(
        _ value: WidgetValue, source: WidgetSource, sourceWritesParse: Bool, contract: WidgetContract = .current
    ) throws -> WidgetView {
        guard let fields = value.object else { throw WidgetSpecProblem([], "view must be a mapping with a kind") }
        let kinds = contract.views.keys.sorted().joined(separator: ", ")
        guard let kind = fields["kind"]?.string else {
            throw WidgetSpecProblem(["kind"], "view.kind is missing; it is one of \(kinds)")
        }
        guard let spec = contract.views[kind] else {
            throw WidgetSpecProblem(["kind"], "view.kind \"\(kind)\" is not one of \(kinds)")
        }
        let known = spec.fields ?? [:]
        for key in fields.keys.sorted() where key != "kind" && known[key] == nil {
            throw WidgetSpecProblem([key], "view.\(key) is not a field of a \(kind) view")
        }
        guard contract.view(kind, accepts: source.outputToken, sourceKind: source.kind) else {
            let gives = source.outputToken ?? "a session screen"
            throw WidgetSpecProblem(
                ["kind"], "view.kind \"\(kind)\" takes \(spec.accepts.joined(separator: ", ")), and this \(source.kind) source gives \(gives)")
        }
        if kind == "web", sourceWritesParse {
            throw WidgetSpecProblem(["kind"], "a web view loads the page itself: remove source.parse")
        }
        let parsesJSON = source.outputToken == "json"
        for key in fields.keys.sorted() where key != "item" {
            if let text = fields[key]?.string, text.contains(itemPattern) {
                throw WidgetSpecProblem([key], "{{item}} is only for view.item of a list")
            }
        }

        var view = WidgetView(kind: kind)
        if let wrap = fields["wrap"] {
            guard let flag = wrap.bool else { throw WidgetSpecProblem(["wrap"], "view.wrap must be true or false") }
            view.wrap = flag
        }
        if let tail = fields["tail"] {
            guard let lines = tail.number, lines == lines.rounded(), (1...2000).contains(Int(lines)) else {
                throw WidgetSpecProblem(["tail"], "view.tail \(tail.text) is outside 1 to 2000 lines")
            }
            view.tail = Int(lines)
        }
        let needsValue = parsesJSON && valueKinds.contains(kind)
        if let template = fields["value"]?.text {
            guard needsValue else {
                throw WidgetSpecProblem(["value"], "view.value is only for a source that parses json")
            }
            guard JSONPath.isTemplate(template) else {
                throw WidgetSpecProblem(["value"], "view.value holds one {{json.<path>}}, such as {{json.used}}")
            }
            view.value = template
        } else if needsValue {
            throw WidgetSpecProblem(["value"], "view.value picks what to show out of the JSON, such as {{json.used}}")
        }
        view.unit = fields["unit"]?.text
        if let format = fields["format"]?.text {
            guard let parsed = NumberFormat(rawValue: format) else {
                throw WidgetSpecProblem(["format"], "view.format \"\(format)\" is one of plain, percent, bytes, duration")
            }
            view.format = parsed
        }
        if kind == "status" {
            view.okRule = try rule(fields, "ok", source: source)
            view.warnRule = try rule(fields, "warn", source: source)
        } else {
            view.warn = try number(fields, "warn")
            view.crit = try number(fields, "crit")
        }
        view.min = try number(fields, "min") ?? view.min
        view.max = try number(fields, "max") ?? view.max
        if kind == "gauge", let max = view.max, view.min >= max {
            throw WidgetSpecProblem(["min"], "view.min must be below view.max")
        }
        if let zoom = try number(fields, "zoom") {
            guard (0.5...2).contains(zoom) else { throw WidgetSpecProblem(["zoom"], "view.zoom is between 0.5 and 2") }
            view.zoom = zoom
        }
        if let item = fields["item"] {
            guard let itemFields = item.object else { throw WidgetSpecProblem(["item"], "view.item must be a mapping") }
            for key in itemFields.keys.sorted() where !["title", "subtitle", "status", "link"].contains(key) {
                throw WidgetSpecProblem(["item", key], "view.item.\(key) is not a field of a list item")
            }
            for key in itemFields.keys.sorted() {
                let text = itemFields[key]?.text ?? ""
                for match in text.matches(of: itemPattern) where match.1 != nil && !parsesJSON {
                    throw WidgetSpecProblem(
                        ["item", key], "{{item.\(match.1 ?? "")}} needs a source that parses json")
                }
            }
            view.item = ListItemTemplate(
                title: itemFields["title"]?.text ?? "{{item}}", subtitle: itemFields["subtitle"]?.text,
                status: itemFields["status"]?.text, link: itemFields["link"]?.text)
        }
        return view
    }

    private static func number(_ fields: [String: WidgetValue], _ key: String) throws -> Double? {
        guard let value = fields[key] else { return nil }
        switch value {
        case .int, .double: return value.number
        default: throw WidgetSpecProblem([key], "view.\(key) must be a number")
        }
    }

    private static func rule(_ fields: [String: WidgetValue], _ key: String, source: WidgetSource) throws -> StatusRule? {
        guard let text = fields[key]?.text else { return nil }
        guard let rule = StatusRule.parse(text) else {
            throw WidgetSpecProblem([key], "view.\(key) \"\(text)\" is not a rule such as < 300 or == \"ok\"")
        }
        if source.outputToken == ParseMode.text.rawValue, rule.comparesBySize {
            let written = text.trimmingCharacters(in: .whitespaces)
            throw WidgetSpecProblem(
                [key], "view.\(key) \"\(written)\" compares by size, and this \(source.kind) source gives text: use == or !=")
        }
        return rule
    }
}
