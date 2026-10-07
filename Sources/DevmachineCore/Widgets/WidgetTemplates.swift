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

    /// What a `shell: true` line reads: `$DM_INPUT_<NAME>` and
    /// `$DM_CONTEXT_<KEY>`, so a value is never parsed as shell code.
    public var environment: [String: String] {
        var variables: [String: String] = [:]
        for key in inputs.keys.sorted() { variables[Self.variableName("DM_INPUT_", key)] = inputs[key] }
        for key in context.keys.sorted() { variables[Self.variableName("DM_CONTEXT_", key)] = context[key] }
        return variables
    }

    /// The CLI's EnvName: upper case, one `_` for each character outside
    /// A-Z and 0-9, so both sides name the same variable.
    public static func variableName(_ prefix: String, _ key: String) -> String {
        prefix + String(key.unicodeScalars.map { scalar -> Character in
            let upper = scalar.properties.uppercaseMapping.unicodeScalars
            let mapped = upper.count == 1 ? upper.first ?? scalar : scalar
            return ("A"..."Z").contains(mapped) || ("0"..."9").contains(mapped) ? Character(mapped) : "_"
        })
    }

    /// The variable a template reference such as `inputs.disk-path` reads,
    /// or nil for a reference to anything but inputs and context.
    public static func variableName(reference: String) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let key = String(trimmed[trimmed.index(after: dot)...])
        guard !key.isEmpty else { return nil }
        switch trimmed[..<dot] {
        case "inputs": return variableName("DM_INPUT_", key)
        case "context": return variableName("DM_CONTEXT_", key)
        default: return nil
        }
    }
}

/// Why a command source builds nothing, so nothing half-safe ever runs.
public enum WidgetCommandError: Error, Equatable, LocalizedError {
    case refused(String)
    case nothingToRun

    public var errorDescription: String? {
        switch self {
        case let .refused(message): return message
        case .nothingToRun: return "the command source has nothing to run"
        }
    }
}

extension WidgetSource {
    /// Every template resolved, for the approval hash and what a person reads.
    /// A command that holds a template where none may sit is refused.
    public func resolved(with values: TemplateValues) throws -> WidgetSource {
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
            if let refused = ArgvBuilder.refusal(source) { throw WidgetCommandError.refused(refused.message) }
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
        let text = shortest(value, exponentBelow: -6, exponentFrom: 21)
        return text.replacing(/e-0(\d)$/) { "e-\($0.1)" }
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
