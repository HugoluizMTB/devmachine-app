import Foundation

/// What the context sidebar knows about the selected session, as the keys
/// its widgets read. Every key is set, empty when unknown, so a shell line
/// sees the same variables and the approval hash is stable.
public struct SessionContextFacts: Equatable, Sendable {
    public var machine: String
    public var session: String
    public var workspace: String
    public var path: String
    public var repo: String
    public var branch: String
    public var harness: String

    public init(
        machine: String = "", session: String = "", workspace: String = "", path: String = "", repo: String = "",
        branch: String = "", harness: String = ""
    ) {
        self.machine = machine
        self.session = session
        self.workspace = workspace
        self.path = path
        self.repo = repo
        self.branch = branch
        self.harness = harness
    }

    public var values: [String: String] {
        [
            "machine": machine, "session": session, "workspace": workspace, "path": path, "repo": repo,
            "branch": branch, "harness": harness,
        ]
    }
}

/// The sidebar's one context key, set even with nothing selected.
public enum SidebarContext {
    public static func values(selectedWorkspace: String?) -> [String: String] {
        ["selected": selectedWorkspace ?? ""]
    }
}

public struct ContextGitStatus: Equatable, Sendable {
    public let branch: String
    public let repo: String

    public init(branch: String, repo: String) {
        self.branch = branch
        self.repo = repo
    }
}

/// A status-only read for `repo` and `branch`: the Git tab's snapshot has
/// no owner/name and reads far more than a widget needs.
public enum ContextGitProbe {
    public static let body = #"printf '%s\n%s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" "$(git config --get remote.origin.url 2>/dev/null)""#

    public static func parse(_ stdout: String) -> ContextGitStatus {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let branch = lines.first ?? ""
        let remote = lines.count > 1 ? lines[1] : ""
        return ContextGitStatus(branch: branch == "HEAD" ? "" : branch, repo: repo(fromRemote: remote))
    }

    public static func repo(fromRemote url: String) -> String {
        var text = url.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        if let scheme = text.range(of: "://") {
            text = String(text[scheme.upperBound...])
            text = text.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        } else if let colon = text.firstIndex(of: ":"), !text.hasPrefix("/") {
            text = String(text[text.index(after: colon)...])
        }
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return "" }
        return parts.suffix(2).joined(separator: "/")
    }
}

extension ResolvedSource {
    /// Whether a run reads `key`, so the board fetches a costly key (repo,
    /// branch) only when some widget uses it. A package widget declares its
    /// keys; an inline one is read from its templates and shell variables,
    /// and an inline script, whose text the app never sees, reads them all.
    public func reads(contextKey key: String) -> Bool {
        if let contextKeys { return contextKeys.contains(key) }
        if case let .command(command) = source, command.script != nil { return true }
        let variable = TemplateValues.variableName("DM_CONTEXT_", key)
        return Self.strings(in: source).contains {
            Self.template(in: $0, names: key) || Self.variable(variable, isIn: $0)
        }
    }

    /// Only the keys a run reads, so a change to any other leaves it alone.
    public func readContext(_ context: [String: String]) -> [String: String] {
        context.filter { reads(contextKey: $0.key) }
    }

    private static func template(in text: String, names key: String) -> Bool {
        text.matches(of: WidgetSourceReader.templatePattern).contains { match in
            guard let reference = match.1.wholeMatch(of: WidgetSourceReader.referencePattern) else { return false }
            return reference.1 == "context" && reference.2 == key
        }
    }

    private static func variable(_ name: String, isIn text: String) -> Bool {
        var rest = text[...]
        while let found = rest.range(of: name) {
            let next = rest[found.upperBound...].first
            if next.map({ !($0.isLetter || $0.isNumber || $0 == "_") }) ?? true { return true }
            rest = rest[found.upperBound...]
        }
        return false
    }

    private static func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        return Mirror(reflecting: value).children.flatMap { strings(in: $0.value) }
    }
}
