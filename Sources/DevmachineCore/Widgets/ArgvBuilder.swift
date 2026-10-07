import Foundation

/// What runs on the target, before deciding how to reach it.
public enum TargetCommand: Equatable, Sendable {
    case argv([String])
    case shellLine(String)
    case packageScript(package: String, script: String, args: [String])
}

/// A process ready to start, so tests can check exactly what would run.
public struct ProcessInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]?
    public var currentDirectory: String?

    public init(executable: String, arguments: [String], environment: [String: String]? = nil, currentDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
    }
}

/// The devmachine binary and the environment the app hands it (ssh agent).
public struct CLIInvocationContext: Equatable, Sendable {
    public var executable: String
    public var environment: [String: String]

    public init(executable: String, environment: [String: String]) {
        self.executable = executable
        self.environment = environment
    }
}

/// An app opened from Finder inherits launchd's bare PATH, so the folders
/// a person's tools live in are added after it.
public enum LocalPATH {
    public static func value(inherited: String?, home: String) -> String {
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        let parts = (inherited ?? "").split(separator: ":").map(String.init) + extra
        return parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }
}

/// The one place a widget's argv or shell line is built. Every value is one
/// argv item unless the source asked for a shell, and then it is quoted.
public enum ArgvBuilder {
    public static let env = "/usr/bin/env"
    public static let shell = "/bin/sh"

    /// Resolves the source's templates itself, so a template the shell could
    /// unquote never reaches a line.
    public static func command(
        _ unresolved: CommandSource, values: TemplateValues = .none, package: String?, packagePath: String?
    ) throws -> TargetCommand {
        guard case let .command(source) = try WidgetSource.command(unresolved).resolved(with: values) else {
            throw WidgetCommandError.nothingToRun
        }
        if let script = source.script {
            guard let package else { return .argv([script] + source.args) }
            if source.target == .local {
                let path = packagePath ?? ""
                let base = path.hasSuffix("/") ? String(path.dropLast()) : path
                return .argv(["\(base)/\(script)"] + source.args)
            }
            return .packageScript(package: package, script: script, args: source.args)
        }
        guard let run = source.run, !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WidgetCommandError.nothingToRun
        }
        guard source.shell else { return .argv([run] + source.args) }
        return .shellLine(([run] + source.args.map(RemoteCommands.shellSingleQuoted)).joined(separator: " "))
    }

    /// `env` reads a leading - as its own option and a word with = as a
    /// variable, so such a program name would never run as written.
    public static func envWouldMisread(_ program: String) -> Bool {
        !program.contains("/") && (program.hasPrefix("-") || program.contains("="))
    }

    public static func prompt(_ source: PromptSource) -> TargetCommand {
        switch source.harness {
        case .claude: return .argv(["claude", "-p", "--", source.prompt])
        case .codex: return .argv(["codex", "exec", "--skip-git-repo-check", "--", source.prompt])
        }
    }

    public static func tmuxCapture(session: String) -> TargetCommand {
        .argv(["tmux", "capture-pane", "-p", "-e", "-t", session])
    }

    /// `devmachine run` as the CLI plan's Appendix B fixes it: `--machine`
    /// before `run`, `--workspace` after it, never both.
    public static func remote(_ command: TargetCommand, target: WidgetTarget, cli: CLIInvocationContext) -> ProcessInvocation? {
        let head: [String]
        switch target {
        case .local: return nil
        case let .machine(name): head = ["--machine", name, "run", "--no-log"]
        case let .workspace(name): head = ["run", "--workspace", name, "--no-log"]
        }
        let tail: [String]
        switch command {
        case let .argv(words): tail = ["--argv", "--"] + words
        case let .shellLine(line): tail = ["--", line]
        case let .packageScript(package, script, args): tail = ["--package", package, "--script", script, "--"] + args
        }
        return ProcessInvocation(executable: cli.executable, arguments: head + tail, environment: cli.environment)
    }

    public static func local(_ command: TargetCommand, environment: [String: String], home: String) -> ProcessInvocation? {
        var variables = environment
        variables["PATH"] = LocalPATH.value(inherited: environment["PATH"], home: home)
        switch command {
        case let .argv(words):
            guard let first = words.first, !first.isEmpty else { return nil }
            if first.contains("/") {
                return ProcessInvocation(
                    executable: first, arguments: Array(words.dropFirst()), environment: variables, currentDirectory: home)
            }
            if envWouldMisread(first) { return nil }
            return ProcessInvocation(executable: env, arguments: words, environment: variables, currentDirectory: home)
        case let .shellLine(line):
            return ProcessInvocation(executable: shell, arguments: ["-c", line], environment: variables, currentDirectory: home)
        case .packageScript:
            return nil
        }
    }
}
