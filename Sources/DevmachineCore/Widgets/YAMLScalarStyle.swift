import Foundation

/// Writes scalars the way the CLI's YAML library (go-yaml v3) does, so a
/// board saved by the app and one saved by the CLI are the same bytes.
enum YAMLScalarStyle {
    enum Context {
        case block
        case flow
    }

    static func text(_ value: String, in context: Context, quoteYAML11Words: Bool = false) -> String {
        if value.unicodeScalars.contains(where: isBreak) { return doubleQuoted(value) }
        if resolvesToNonText(value) || quoteYAML11Words && (isYAML11Boolean(value) || isBase60Float(value)) {
            return doubleQuoted(value)
        }
        let analysis = Analysis(value)
        if context == .flow ? analysis.flowPlainAllowed : analysis.blockPlainAllowed { return value }
        return analysis.singleQuotedAllowed ? singleQuoted(value) : doubleQuoted(value)
    }

    /// go-yaml formats a float with Go's `%g` at the shortest precision, and
    /// spells infinity and NaN as `.inf`, `-.inf` and `.nan`.
    static func number(_ value: Double) -> String {
        if value.isNaN { return ".nan" }
        if value.isInfinite { return value < 0 ? "-.inf" : ".inf" }
        return GoFloat.shortest(value, exponentBelow: -4, exponentFrom: 6)
    }

    private static let nonTextWords: Set<String> = [
        "true", "True", "TRUE", "false", "False", "FALSE", "", "~", "null", "Null", "NULL",
        ".nan", ".NaN", ".NAN", ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF", "-.inf", "-.Inf", "-.INF", "<<",
    ]

    private static let yaml11Booleans: Set<String> = [
        "y", "Y", "yes", "Yes", "YES", "on", "On", "ON", "n", "N", "no", "No", "NO", "off", "Off", "OFF",
    ]

    static func resolvesToNonText(_ value: String) -> Bool {
        if nonTextWords.contains(value) { return true }
        guard let first = value.first else { return false }
        if first == "." {
            return value.wholeMatch(of: /\.[0-9]+([eE][-+]?[0-9]+)?/) != nil
        }
        guard first == "+" || first == "-" || first.isASCII && first.isNumber else { return false }
        if isTimestamp(value) { return true }
        let plain = value.replacingOccurrences(of: "_", with: "")
        if plain.wholeMatch(of: /[-+]?(0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+|[0-9]+)/) != nil { return true }
        if plain.wholeMatch(of: /[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?/) != nil {
            return Double(plain)?.isFinite ?? false
        }
        return false
    }

    private static func isTimestamp(_ value: String) -> Bool {
        value.wholeMatch(
            of: /[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}([Tt][0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}(\.[0-9]+)?(Z|[-+][0-9]{2}:[0-9]{2})| [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}(\.[0-9]+)?)?/
        ) != nil
    }

    private static func isYAML11Boolean(_ value: String) -> Bool { yaml11Booleans.contains(value) }

    private static func isBase60Float(_ value: String) -> Bool {
        value.wholeMatch(of: /[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+(\.[0-9_]*)?/) != nil
    }

    private static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
        [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains(scalar.value)
    }

    private static func isBlank(_ scalar: Unicode.Scalar) -> Bool { scalar == " " || scalar == "\t" }

    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A, 0x20...0x7E, 0xA0...0xD7FF: return true
        case 0xE000...0xFFFD: return scalar.value != 0xFEFF
        default: return false
        }
    }

    private struct Analysis {
        var flowPlainAllowed = true
        var blockPlainAllowed = true
        var singleQuotedAllowed = true

        init(_ value: String) {
            let scalars = Array(value.unicodeScalars)
            var flowIndicators = false
            var blockIndicators = false
            var special = false
            if value.hasPrefix("---") || value.hasPrefix("...") {
                flowIndicators = true
                blockIndicators = true
            }
            var precededByWhitespace = true
            for (index, scalar) in scalars.enumerated() {
                let followedByWhitespace = index + 1 >= scalars.count || isBlank(scalars[index + 1])
                if index == 0 {
                    switch scalar {
                    case "#", ",", "[", "]", "{", "}", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`":
                        flowIndicators = true
                        blockIndicators = true
                    case "?", ":":
                        flowIndicators = true
                        if followedByWhitespace { blockIndicators = true }
                    case "-":
                        if followedByWhitespace {
                            flowIndicators = true
                            blockIndicators = true
                        }
                    default: break
                    }
                } else {
                    switch scalar {
                    case ",", "?", "[", "]", "{", "}":
                        flowIndicators = true
                    case ":":
                        flowIndicators = true
                        if followedByWhitespace { blockIndicators = true }
                    case "#":
                        if precededByWhitespace {
                            flowIndicators = true
                            blockIndicators = true
                        }
                    default: break
                    }
                }
                if scalar == "\t" || !isPrintable(scalar) { special = true }
                precededByWhitespace = isBlank(scalar) || isBreak(scalar)
            }
            let edgeSpace = scalars.first == " " || scalars.last == " "
            if edgeSpace || special {
                flowPlainAllowed = false
                blockPlainAllowed = false
            }
            if special { singleQuotedAllowed = false }
            if flowIndicators { flowPlainAllowed = false }
            if blockIndicators { blockPlainAllowed = false }
        }
    }

    private static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func doubleQuoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            let mustEscape = !isPrintable(scalar) || scalar.value == 0xFEFF || isBreak(scalar)
                || scalar == "\"" || scalar == "\\"
            guard mustEscape else {
                out.unicodeScalars.append(scalar)
                continue
            }
            out += "\\" + escape(scalar)
        }
        return out + "\""
    }

    private static func escape(_ scalar: Unicode.Scalar) -> String {
        switch scalar.value {
        case 0x00: return "0"
        case 0x07: return "a"
        case 0x08: return "b"
        case 0x09: return "t"
        case 0x0A: return "n"
        case 0x0B: return "v"
        case 0x0C: return "f"
        case 0x0D: return "r"
        case 0x1B: return "e"
        case 0x22: return "\""
        case 0x5C: return "\\"
        case 0x85: return "N"
        case 0xA0: return "_"
        case 0x2028: return "L"
        case 0x2029: return "P"
        case ...0xFF: return "x" + hex(scalar.value, width: 2)
        case ...0xFFFF: return "u" + hex(scalar.value, width: 4)
        default: return "U" + hex(scalar.value, width: 8)
        }
    }

    private static func hex(_ value: UInt32, width: Int) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
