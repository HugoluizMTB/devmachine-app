import Foundation

/// Takes secrets out of a line before it reaches a log file. Unlike
/// `BugReport.redact`, it keeps addresses, host names, machine, workspace and
/// user names and paths: the log stays on this Mac, and those are what an
/// install problem is read from. The rules match the CLI's own log, so both
/// files read alike.
public enum LogRedactor {
    public static let mask = "***"
    public static let maxArgumentLength = 300

    static let sensitiveName = #"(?:token|secret|password|passwd|api[_-]?key|private[_-]?key|auth)"#

    public static func redact(_ text: String) -> String {
        var text = text
        for rule in rules {
            text = rule.regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rule.template)
        }
        return text
    }

    /// A command line: the value after `secrets set NAME`, the value of a
    /// flag with a secret's name and an `UPPER_NAME=value` argument are taken
    /// out, then every argument goes through `redact(_:)` and is cut to a
    /// length a log line can carry.
    public static func redact(arguments: [String]) -> [String] {
        var result: [String] = []
        var hideNext = false
        for (index, argument) in arguments.enumerated() {
            if hideNext {
                result.append(mask)
                hideNext = false
                continue
            }
            if isSecretValue(at: index, in: arguments) {
                result.append(mask)
                continue
            }
            if let (flag, hasValue) = sensitiveFlag(argument) {
                result.append(hasValue ? flag + "=" + mask : flag)
                hideNext = !hasValue && !flag.hasSuffix("-stdin") && !flag.hasSuffix("-file")
                    && index + 1 < arguments.count && !arguments[index + 1].hasPrefix("-")
                continue
            }
            if let name = environmentName(argument) {
                result.append(name + "=" + mask)
                continue
            }
            result.append(cut(redact(argument)))
        }
        return result
    }

    private static func isSecretValue(at index: Int, in arguments: [String]) -> Bool {
        guard index >= 3, !arguments[index].hasPrefix("-") else { return false }
        let verb = arguments[index - 3]
        return (verb == "secrets" || verb == "secret") && arguments[index - 2] == "set"
    }

    private static let flagPattern = regex(
        #"^(--?(?:value|[A-Za-z0-9_-]*"# + sensitiveName + #"[A-Za-z0-9_-]*))(=.*)?$"#, caseless: true)
    private static let environmentPattern = regex(#"^([A-Z_][A-Z0-9_]*)=.+$"#)

    private static func sensitiveFlag(_ argument: String) -> (String, Bool)? {
        let range = NSRange(argument.startIndex..., in: argument)
        guard let match = flagPattern.firstMatch(in: argument, range: range),
              let flag = Range(match.range(at: 1), in: argument)
        else { return nil }
        return (String(argument[flag]), match.range(at: 2).location != NSNotFound)
    }

    private static func environmentName(_ argument: String) -> String? {
        let range = NSRange(argument.startIndex..., in: argument)
        guard let match = environmentPattern.firstMatch(in: argument, range: range),
              let name = Range(match.range(at: 1), in: argument)
        else { return nil }
        return String(argument[name])
    }

    private static func cut(_ argument: String) -> String {
        argument.count > maxArgumentLength ? String(argument.prefix(maxArgumentLength)) + "…" : argument
    }

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
    }

    private static func regex(_ pattern: String, caseless: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: caseless ? [.caseInsensitive, .anchorsMatchLines] : [.anchorsMatchLines])
    }

    private static let rules: [Rule] = [
        Rule(regex: regex(#"-----BEGIN ([A-Z0-9 ]*)PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\z)"#),
             template: "-----BEGIN $1PRIVATE KEY----- " + mask),
        Rule(regex: regex(#"(authorization["']?\s*[:=]\s*["']?)[^"'\r\n]+"#, caseless: true), template: "$1" + mask),
        Rule(regex: regex(#"\b(bearer\s+)(?!\*\*\*)[A-Za-z0-9._~+/=-]+"#, caseless: true), template: "$1" + mask),
        Rule(regex: regex(#"\b(gh[pousr]_)[A-Za-z0-9]{16,}"#), template: "$1" + mask),
        Rule(regex: regex(#"\b(github_pat_)[A-Za-z0-9_]{16,}"#), template: "$1" + mask),
        Rule(regex: regex(#"\b(sk-)[A-Za-z0-9_-]{16,}"#), template: "$1" + mask),
        Rule(regex: regex(#"\b(tskey-)[A-Za-z0-9_-]+"#), template: "$1" + mask),
        Rule(regex: regex(#"([A-Za-z][A-Za-z0-9+.-]*://[^\s:/@]+):[^\s@/]+@"#), template: "$1:" + mask + "@"),
        Rule(regex: regex(#"("[^"\n]*"# + sensitiveName + #"[^"\n]*"\s*:\s*)("(?:[^"\\]|\\.)*"|[^\s,}\]]+)"#, caseless: true),
             template: "$1\"" + mask + "\""),
        Rule(regex: regex(#"('[^'\n]*"# + sensitiveName + #"[^'\n]*'\s*:\s*)('(?:[^'\\]|\\.)*'|[^\s,}\]]+)"#, caseless: true),
             template: "$1'" + mask + "'"),
        Rule(regex: regex(#"([A-Za-z0-9_.-]*"# + sensitiveName + #"[A-Za-z0-9_.-]*\s*=\s*)(?!\*\*\*)("[^"]*"|'[^']*'|[^\s,;&"']+)"#,
                          caseless: true),
             template: "$1" + mask),
        Rule(regex: regex(#"^([+-]?[ \t]*(?:export\s+)?[A-Z][A-Z0-9_]*=)(?!\*\*\*$)(\S.*)$"#), template: "$1" + mask),
    ]
}
