import Foundation

/// Where a source runs: this Mac, or a machine or workspace through the CLI.
public enum WidgetTarget: Hashable, Sendable {
    case local
    case machine(String)
    case workspace(String)
}

/// `continuous` is a stream: it runs while the widget is on screen.
public enum WidgetEvery: Hashable, Sendable {
    case manual
    case interval(TimeInterval)
    case continuous

    public var seconds: TimeInterval? {
        if case let .interval(value) = self { return value }
        return nil
    }
}

public enum ParseMode: String, Hashable, Sendable {
    case text, lines, number, json, ansi, status
}

public enum CommandMode: String, Hashable, Sendable {
    case poll, stream
}

public enum PromptHarness: String, Hashable, Sendable {
    case claude, codex
}

public struct ProviderSource: Hashable, Sendable {
    public var name: String
    public var with: [String: String]
    public var every: String

    public init(name: String, with: [String: String], every: String) {
        self.name = name
        self.with = with
        self.every = every
    }
}

public struct CommandSource: Hashable, Sendable {
    public var run: String?
    public var script: String?
    public var args: [String]
    public var shell: Bool
    public var target: WidgetTarget
    public var every: WidgetEvery
    public var timeout: TimeInterval
    public var mode: CommandMode
    public var keep: Int
    public var parse: ParseMode

    public init(
        run: String?, script: String?, args: [String], shell: Bool, target: WidgetTarget, every: WidgetEvery,
        timeout: TimeInterval, mode: CommandMode, keep: Int, parse: ParseMode
    ) {
        self.run = run
        self.script = script
        self.args = args
        self.shell = shell
        self.target = target
        self.every = every
        self.timeout = timeout
        self.mode = mode
        self.keep = keep
        self.parse = parse
    }
}

public struct URLSource: Hashable, Sendable {
    public var url: String
    public var every: WidgetEvery
    public var timeout: TimeInterval
    public var parse: ParseMode

    public init(url: String, every: WidgetEvery, timeout: TimeInterval, parse: ParseMode) {
        self.url = url
        self.every = every
        self.timeout = timeout
        self.parse = parse
    }
}

/// `permissionMode` is the harness's own mode name, nil for its default.
public struct PromptSource: Hashable, Sendable {
    public var harness: PromptHarness
    public var prompt: String
    public var target: WidgetTarget
    public var every: WidgetEvery
    public var timeout: TimeInterval
    public var permissionMode: String?

    public init(
        harness: PromptHarness, prompt: String, target: WidgetTarget, every: WidgetEvery, timeout: TimeInterval,
        permissionMode: String? = nil
    ) {
        self.harness = harness
        self.prompt = prompt
        self.target = target
        self.every = every
        self.timeout = timeout
        self.permissionMode = permissionMode
    }
}

public struct SessionSource: Hashable, Sendable {
    public var target: WidgetTarget
    public var session: String
    public var every: WidgetEvery

    public init(target: WidgetTarget, session: String, every: WidgetEvery) {
        self.target = target
        self.session = session
        self.every = every
    }
}

public enum WidgetSource: Hashable, Sendable {
    case provider(ProviderSource)
    case command(CommandSource)
    case url(URLSource)
    case prompt(PromptSource)
    case session(SessionSource)
    case packageProvider(PackageProviderSource)

    public var kind: String {
        switch self {
        case .provider, .packageProvider: return "provider"
        case .command: return "command"
        case .url: return "url"
        case .prompt: return "prompt"
        case .session: return "session"
        }
    }

    /// What a view's `accepts` is matched against; a session gives none, so
    /// only `kind:session` takes it.
    public var outputToken: String? {
        switch self {
        case let .provider(source): return source.name
        case let .command(source): return source.parse.rawValue
        case let .url(source): return source.parse.rawValue
        case .prompt: return "text"
        case .session: return nil
        case .packageProvider: return ParseMode.json.rawValue
        }
    }

    public var every: WidgetEvery {
        switch self {
        case let .provider(source): return GoDuration.seconds(source.every).map(WidgetEvery.interval) ?? .manual
        case let .command(source): return source.every
        case let .url(source): return source.every
        case let .prompt(source): return source.every
        case let .session(source): return source.every
        case let .packageProvider(source): return source.every
        }
    }

    public var target: WidgetTarget? {
        switch self {
        case .provider, .url: return nil
        case let .command(source): return source.target
        case let .prompt(source): return source.target
        case let .session(source): return source.target
        case let .packageProvider(source): return source.target
        }
    }

    /// Runs a program somewhere, so a widget from code the owner did not
    /// write asks before it does.
    public var runsCode: Bool {
        switch self {
        case .command, .prompt, .session, .packageProvider: return true
        case .provider, .url: return false
        }
    }
}

/// What a widget's templates may name: a package widget its declared inputs
/// and context; a widget written in a board no inputs, and only the context
/// keys its board's area gives.
public enum WidgetScope: Hashable, Sendable {
    case package(inputs: Set<String>, contextKeys: Set<String>)
    case inline(contextKeys: Set<String>)

    var inputs: Set<String>? {
        if case let .package(inputs, _) = self { return inputs }
        return nil
    }

    var contextKeys: Set<String> {
        switch self {
        case let .package(_, keys), let .inline(keys): return keys
        }
    }
}

public struct WidgetSpecProblem: Error, Equatable, Sendable, CustomStringConvertible {
    public let path: [String]
    public let message: String

    public init(_ path: [String], _ message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { message }
}
