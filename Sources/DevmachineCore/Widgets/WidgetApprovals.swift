import CryptoKit
import Foundation

/// What an approval is about: only what runs and where, so a change of
/// frequency keeps it and any change of the command asks again.
public enum ApprovalSubject {
    /// A shell line reads its values from the environment, so those values
    /// are part of what runs and a changed one asks again.
    public static func hash(_ source: WidgetSource, values: TemplateValues) throws -> String? {
        let filled = try subject(source, values: values)
        return hash(filled.source, environment: filled.environment)
    }

    /// The source with its templates filled and, for a shell line, the
    /// values it reads: what the hash covers and the card shows.
    static func subject(
        _ source: WidgetSource, values: TemplateValues
    ) throws -> (source: WidgetSource, environment: [String: String]) {
        let resolved = try source.resolved(with: values)
        guard case let .command(command) = source, command.shell else { return (resolved, [:]) }
        return (resolved, values.environment)
    }

    /// What the runner checks right before a run and what the card records a
    /// decision for: the same inputs and the same real context as the run.
    public static func hash(for resolved: ResolvedSource, context: [String: String]) throws -> String? {
        try hash(resolved.source, values: resolved.values(context: context))
    }

    /// A third-party widget's subject carries its package's commit, so code
    /// that changed under an unchanged widget asks again.
    public static func canonicalJSON(
        _ source: WidgetSource, environment: [String: String] = [:], packageCommit: String? = nil
    ) -> String? {
        func target(_ target: WidgetTarget) -> WidgetValue {
            switch target {
            case .local: return .string("local")
            case let .machine(name): return .object(["machine": .string(name)])
            case let .workspace(name): return .object(["workspace": .string(name)])
            }
        }
        var fields: [String: WidgetValue]
        switch source {
        case .provider, .url:
            return nil
        case let .command(command):
            fields = [
                "kind": .string("command"), "args": .list(command.args.map(WidgetValue.string)),
                "shell": .bool(command.shell), "target": target(command.target),
            ]
            if let run = command.run { fields["run"] = .string(run) }
            if let script = command.script { fields["script"] = .string(script) }
            if !environment.isEmpty { fields["env"] = .object(environment.mapValues(WidgetValue.string)) }
        case let .prompt(prompt):
            fields = [
                "kind": .string("prompt"), "harness": .string(prompt.harness.rawValue), "prompt": .string(prompt.prompt),
                "target": target(prompt.target),
            ]
        case let .session(session):
            fields = ["kind": .string("session"), "session": .string(session.session), "target": target(session.target)]
        case let .packageProvider(provider):
            guard case let .packageCommand(package, command, args)? = try? ArgvBuilder.packageProvider(provider) else {
                return nil
            }
            fields = [
                "kind": .string("provider"), "name": .string("\(package)/\(command)"),
                "args": .list(args.map(WidgetValue.string)), "target": target(provider.target),
            ]
        }
        if let packageCommit { fields["package_commit"] = .string(packageCommit) }
        return WidgetValue.object(fields).canonicalJSON
    }

    public static func hash(_ source: WidgetSource, environment: [String: String] = [:], packageCommit: String? = nil) -> String? {
        canonicalJSON(source, environment: environment, packageCommit: packageCommit).map { text in
            SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
}

public enum ApprovalDecision: String, Codable, Sendable {
    case allowed, denied
}

/// `waiting` and `denied` carry the hash so the card can record a decision
/// for exactly what it showed.
public enum ApprovalState: Equatable, Sendable {
    case notNeeded
    case waiting(hash: String)
    case allowed
    case denied(hash: String)

    public var canRun: Bool {
        switch self {
        case .notNeeded, .allowed: return true
        case .waiting, .denied: return false
        }
    }
}

/// Decisions by hash, so the same command in two boards is decided once.
public struct WidgetApprovals: Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let decision: ApprovalDecision
        public let summary: String
        public let decidedAt: Date

        enum CodingKeys: String, CodingKey {
            case decision, summary
            case decidedAt = "decided_at"
        }
    }

    public private(set) var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public func decision(for hash: String) -> ApprovalDecision? { entries[hash]?.decision }

    public mutating func record(_ decision: ApprovalDecision, hash: String, summary: String, at date: Date) {
        entries[hash] = Entry(decision: decision, summary: summary, decidedAt: date)
    }

    public func state(needsApproval: Bool, hash: String?) -> ApprovalState {
        guard needsApproval else { return .notNeeded }
        guard let hash else { return .waiting(hash: "") }
        switch decision(for: hash) {
        case .allowed?: return .allowed
        case .denied?: return .denied(hash: hash)
        case nil: return .waiting(hash: hash)
        }
    }
}

/// Kept in Application Support, never in the CLI's config folder: an agent
/// that can write a board must not be able to approve it too.
public struct WidgetApprovalsFile: Sendable {
    private struct File: Codable {
        let version: Int
        let approvals: [String: WidgetApprovals.Entry]
    }

    public static let version = 1

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/widget-approvals.json")
    }

    public let fileURL: URL

    public init(fileURL: URL = WidgetApprovalsFile.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func load() -> WidgetApprovals {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? decoder.decode(File.self, from: data), file.version == Self.version
        else { return WidgetApprovals() }
        return WidgetApprovals(entries: file.approvals)
    }

    public func save(_ approvals: WidgetApprovals) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(File(version: Self.version, approvals: approvals.entries))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// The words a person reads before allowing a widget: what runs, where and how often.
public enum ApprovalCopy {
    public static func what(_ source: WidgetSource, environment: [String: String] = [:]) -> String {
        switch source {
        case let .command(command):
            let program = command.run ?? command.script ?? ""
            guard !command.shell else {
                let variables = environment.keys.sorted().map { "\($0)=\(word(environment[$0] ?? ""))" }
                return (variables + [program] + command.args.map(RemoteCommands.shellSingleQuoted)).joined(separator: " ")
            }
            return ([program] + command.args.map(word)).joined(separator: " ")
        case let .prompt(prompt):
            return "Ask \(prompt.harness == .claude ? "Claude" : "Codex"): \(prompt.prompt)"
        case let .session(session):
            return "Read the screen of session \(session.session)"
        case let .url(url):
            return url.url
        case let .packageProvider(provider):
            guard case let .packageCommand(package, command, args)? = try? ArgvBuilder.packageProvider(provider) else {
                return provider.name
            }
            return (["\(package)/\(command)"] + args.map(word)).joined(separator: " ")
        case let .provider(provider):
            return provider.name
        }
    }

    public static func place(_ target: WidgetTarget?) -> String {
        switch target {
        case .local?, nil: return "on this Mac"
        case let .machine(name)?: return "on machine \(name)"
        case let .workspace(name)?: return "in workspace \(name)"
        }
    }

    public static func howOften(_ every: WidgetEvery) -> String {
        switch every {
        case .manual: return "when you press ▶"
        case .continuous: return "all the time while it is on screen"
        case let .interval(seconds): return "every " + GoDurationText.short(seconds)
        }
    }

    private static func word(_ text: String) -> String {
        text.isEmpty || text.contains(where: { $0.isWhitespace || "'\"$`\\;|&<>(){}*?!#~".contains($0) })
            ? RemoteCommands.shellSingleQuoted(text) : text
    }
}

/// The card and the stored summary read the source filled the same way the
/// run fills it, so the owner approves exactly what the hash covers.
public struct ApprovalPrompt: Equatable, Sendable {
    public let what: String
    public let place: String
    public let howOften: String

    public var summary: String { "\(what) \(place), \(howOften)" }

    public init(_ resolved: ResolvedSource, context: [String: String]) {
        let shown = (try? ApprovalSubject.subject(resolved.source, values: resolved.values(context: context)))
            ?? (source: resolved.source, environment: [:])
        what = ApprovalCopy.what(shown.source, environment: shown.environment)
        place = ApprovalCopy.place(shown.source.target)
        howOften = ApprovalCopy.howOften(resolved.every)
    }
}

/// "1m", "90s" → "1m30s": the way the board writes durations.
public enum GoDurationText {
    public static func short(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        var text = ""
        if hours > 0 { text += "\(hours)h" }
        if minutes > 0 { text += "\(minutes)m" }
        if rest > 0 || text.isEmpty { text += "\(rest)s" }
        return text
    }
}
