import Foundation

/// The values a widget's templates read. A key missing at run time resolves
/// to empty text, as the CLI documents.
public struct TemplateValues: Equatable, Sendable {
    public var inputs: [String: String]
    public var context: [String: String]

    public static let none = TemplateValues(inputs: [:], context: [:])

    public init(inputs: [String: String], context: [String: String]) {
        self.inputs = inputs
        self.context = context
    }

    public func resolve(_ text: String, escape: (String) -> String = { $0 }) -> String {
        text.replacing(/\{\{\s*(inputs|context)\.([A-Za-z0-9_.-]+)\s*\}\}/) { match in
            let key = String(match.2)
            let value = match.1 == "inputs" ? inputs[key] : context[key]
            return escape(value ?? "")
        }
    }
}

extension WidgetSource {
    /// Every template resolved. In a shell line each value is quoted for
    /// the shell; anywhere else it stays one literal word.
    public func resolved(with values: TemplateValues) -> WidgetSource {
        func plain(_ text: String) -> String { values.resolve(text) }
        func target(_ target: WidgetTarget) -> WidgetTarget {
            switch target {
            case .local: return .local
            case let .machine(name): return .machine(plain(name))
            case let .workspace(name): return .workspace(plain(name))
            }
        }
        switch self {
        case var .provider(source):
            source.with = source.with.mapValues(plain)
            return .provider(source)
        case var .command(source):
            source.run = source.run.map { source.shell ? values.resolve($0, escape: RemoteCommands.shellSingleQuoted) : plain($0) }
            source.args = source.args.map(plain)
            source.target = target(source.target)
            return .command(source)
        case var .url(source):
            source.url = plain(source.url)
            return .url(source)
        case var .prompt(source):
            source.prompt = plain(source.prompt)
            source.target = target(source.target)
            return .prompt(source)
        case var .session(source):
            source.session = plain(source.session)
            source.target = target(source.target)
            return .session(source)
        }
    }
}

/// Go's shortest float text. The CLI hands numbers over as Go JSON, so a
/// template sees `3` for 3.0 and `0.00001`, never Swift's `3.0` or `1e-05`.
enum GoFloat {
    static func json(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Inf" : "+Inf" }
        return shortest(value, exponentBelow: -6, exponentFrom: 21)
    }

    static func shortest(_ value: Double, exponentBelow: Int, exponentFrom: Int) -> String {
        let described = String(describing: value)
        let negative = described.hasPrefix("-")
        let unsigned = negative ? String(described.dropFirst()) : described
        let parts = unsigned.split(separator: "e", maxSplits: 1)
        let mantissa = String(parts[0])
        let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let pieces = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(pieces[0])
        let fraction = pieces.count > 1 ? String(pieces[1]) : ""
        var digits = whole + fraction
        var point = whole.count + exponent
        while digits.count > 1, digits.first == "0" {
            digits.removeFirst()
            point -= 1
        }
        while digits.count > 1, digits.last == "0" { digits.removeLast() }
        if digits == "0" { point = 1 }
        let sign = negative ? "-" : ""
        let decimalExponent = point - 1
        if decimalExponent < exponentBelow || decimalExponent >= exponentFrom {
            return sign + scientific(digits: digits, exponent: decimalExponent)
        }
        if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
        if point >= digits.count { return sign + digits + String(repeating: "0", count: point - digits.count) }
        return sign + String(digits.prefix(point)) + "." + String(digits.dropFirst(point))
    }

    private static func scientific(digits: String, exponent: Int) -> String {
        let mantissa = digits.count == 1 ? digits : String(digits.prefix(1)) + "." + String(digits.dropFirst())
        let magnitude = abs(exponent)
        return mantissa + "e" + (exponent < 0 ? "-" : "+") + (magnitude < 10 ? "0" : "") + String(magnitude)
    }
}
