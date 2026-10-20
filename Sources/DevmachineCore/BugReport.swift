import Foundation

/// A bug report the person opens in their browser, reviews and submits
/// themselves: the app never posts anything. The repository is public, so
/// everything personal or secret is taken out of the text first.
public struct BugReport: Equatable, Sendable {
    public static let newIssueURL = "https://github.com/mydevmachine/devmachine/issues/new"
    /// Browsers and GitHub cut a longer address.
    public static let maxURLLength = 7000
    public static let maxLines = 40
    /// Where the full logs are, for the person to attach.
    public static let logsHint = "More detail: in the app, Help > Logs > Save All Logs… writes a zip of the "
        + "app's and the CLI's logs (secrets taken out) to the Desktop. Drag it into this issue. "
        + "The app's own log is in ~/Library/Logs/Devmachine."

    /// What the person typed or this Mac is called, to be taken out by name.
    public struct Context: Equatable, Sendable {
        public var home: String
        public var user: String
        public var hosts: [String]
        public var domains: [String]
        public var machines: [String]
        public var workspaces: [String]

        public init(
            home: String, user: String, hosts: [String] = [], domains: [String] = [],
            machines: [String] = [], workspaces: [String] = []
        ) {
            self.home = home
            self.user = user
            self.hosts = hosts
            self.domains = domains
            self.machines = machines
            self.workspaces = workspaces
        }
    }

    public var title: String
    public var appVersion: String
    public var cliVersion: String
    public var macOS: String
    public var arch: String
    public var stepID: String
    public var command: String
    public var exitCode: Int32?
    public var lines: [String]

    public init(
        title: String, appVersion: String, cliVersion: String, macOS: String, arch: String,
        stepID: String, command: String, exitCode: Int32?, lines: [String]
    ) {
        self.title = title
        self.appVersion = appVersion
        self.cliVersion = cliVersion
        self.macOS = macOS
        self.arch = arch
        self.stepID = stepID
        self.command = command
        self.exitCode = exitCode
        self.lines = lines
    }

    public func body(context: Context, maxLines: Int = BugReport.maxLines) -> String {
        let exit = exitCode.map { String($0) } ?? "none (stopped, or it did not start)"
        let log = lines.suffix(maxLines).joined(separator: "\n")
        let text = """
            **What happened:** \(title)

            - App: \(appVersion)
            - CLI: \(cliVersion)
            - macOS: \(macOS) (\(arch))
            - Step: \(stepID)
            - Command: `\(command)`
            - Exit code: \(exit)

            Last log lines:

            ```
            \(log)
            ```

            \(Self.logsHint)
            """
        return Self.redact(text, context: context)
    }

    /// The new-issue page with the title and body filled in, trimming log
    /// lines from the top until it fits.
    public func url(context: Context) -> URL? {
        let title = Self.redact(title, context: context)
        var count = min(lines.count, Self.maxLines)
        while true {
            let query = "title=" + Self.encode(title) + "&body=" + Self.encode(body(context: context, maxLines: count))
            let address = Self.newIssueURL + "?" + query
            if address.count <= Self.maxURLLength || count == 0 { return URL(string: address) }
            count -= 1
        }
    }

    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - Redaction

    public static func redact(_ text: String, context: Context) -> String {
        var text = text
        text = replace(#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, in: text,
                       with: "<redacted key>")
        text = replace(#"(?i)\b(password|passwd|pass|token|secret|api[_-]?key|access[_-]?key|auth|key)(\s*[:=]\s*)\S+"#,
                       in: text, with: "$1$2<redacted>")
        text = replace(#"(?i)\bbearer\s+\S+"#, in: text, with: "Bearer <redacted>")
        text = replace(#"\b(?:ghp|gho|ghs|ghu|github_pat|glpat|sk|xoxb|xoxp)[-_][A-Za-z0-9_-]{8,}"#, in: text,
                       with: "<redacted>")
        text = replace(#"SHA256:[A-Za-z0-9+/=]{16,}"#, in: text, with: "<fingerprint>")
        text = replace(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text, with: "<email>")
        if !context.home.isEmpty { text = text.replacingOccurrences(of: context.home, with: "~") }
        for host in context.hosts.filter({ !$0.isEmpty }) {
            text = text.replacingOccurrences(of: host, with: "<host>")
        }
        for domain in context.domains.filter({ !$0.isEmpty }) {
            let escaped = NSRegularExpression.escapedPattern(for: domain)
            text = replace(#"(?:[A-Za-z0-9-]+\.)*"# + escaped + #"\b"#, in: text, with: "<domain>")
        }
        text = replace(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, in: text, with: "<ip>")
        text = replace(#"\b(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}\b"#, in: text, with: "<ip>")
        text = replace(#"\b(?:[0-9A-Fa-f]{1,4}:)+:(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?"#, in: text, with: "<ip>")
        text = replaceWords(context.machines, in: text, with: "<machine>")
        text = replaceWords(context.workspaces, in: text, with: "<workspace>")
        text = replaceWords([context.user], in: text, with: "<user>")
        return text
    }

    /// Whole words only, so `al` never eats the middle of `always`. A name
    /// may hold `-` or `.`, which a regex word boundary would split on.
    private static func replaceWords(_ words: [String], in text: String, with marker: String) -> String {
        var text = text
        for word in words.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: word)
            text = replace(#"(?<![A-Za-z0-9_.-])"# + escaped + #"(?![A-Za-z0-9_-]|\.[A-Za-z0-9])"#, in: text, with: marker)
        }
        return text
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
