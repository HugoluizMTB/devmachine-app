import Foundation

/// What runs on the target, before deciding how to reach it.
public enum TargetCommand: Equatable, Sendable {
    case argv([String])
    case shell(line: String, environment: [String: String])
    case packageScript(package: String, script: String, args: [String])
    case packageCommand(package: String, command: String, args: [String])
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

/// The one place a widget's argv or shell line is built. A value is never
/// part of a shell line: it is one argv item, or an environment variable a
/// `shell: true` line reads.
public enum ArgvBuilder {
    public static let shell = "/bin/sh"
    public static let env = "/usr/bin/env"

    /// Why a command source can never run, in the words the reader uses.
    public static func refusal(_ source: CommandSource) -> (field: String, message: String)? {
        let first = source.run?.firstMatch(of: WidgetSourceReader.templatePattern)
        if source.shell {
            if let first {
                if let name = TemplateValues.variableName(reference: String(first.output.1)) {
                    return ("run", "source.run is a shell line, so it cannot hold \(first.output.0): read it as \"$\(name)\" instead")
                }
                return ("run", "source.run is a shell line, so it cannot hold \(first.output.0): "
                    + "read values as $DM_INPUT_<NAME> or $DM_CONTEXT_<KEY> instead")
            }
            if !source.args.isEmpty {
                return ("args", "a shell line takes no source.args: write the words in source.run, and read values as $DM_INPUT_<NAME>")
            }
            return nil
        }
        if let first {
            return ("run", "source.run cannot hold \(first.output.0): a value must not pick the program — "
                + "name the program in run, and put the value in source.args")
        }
        return nil
    }

    /// Takes the source as written and the values, so a value never becomes
    /// part of a shell line.
    public static func command(
        _ source: CommandSource, values: TemplateValues = .none, package: String?, packagePath: String?
    ) throws -> TargetCommand {
        if let refused = refusal(source) { throw WidgetCommandError.refused(refused.message) }
        let args = source.args.map { values.resolve($0) }
        if let script = source.script {
            guard let package else { return .argv([script] + args) }
            if source.target == .local {
                let path = packagePath ?? ""
                let base = path.hasSuffix("/") ? String(path.dropLast()) : path
                return .argv(["\(base)/\(script)"] + args)
            }
            return .packageScript(package: package, script: script, args: args)
        }
        guard let run = source.run, !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WidgetCommandError.nothingToRun
        }
        if source.shell { return .shell(line: run, environment: values.environment) }
        return .argv([run] + args)
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

    /// A `with` key becomes `--<key>`, so it must read as one flag.
    public static var flagName: Regex<Substring> { /[a-z][a-z0-9_-]*/ }

    /// Each `with` pair is two argv items in key order: a value is never
    /// split, quoted or read by a shell. A NUL byte would cut it short in
    /// the C argv, so it is refused.
    public static func packageProvider(_ source: PackageProviderSource) throws -> TargetCommand {
        guard let parts = PackageProviderName.parts(source.name) else {
            throw WidgetCommandError.refused("source.name \"\(source.name)\" is not <package>/<command>")
        }
        var args: [String] = []
        for key in source.with.keys.sorted() {
            guard key.wholeMatch(of: flagName) != nil else {
                throw WidgetCommandError.refused("source.with.\(key) is not a flag name")
            }
            let value = source.with[key] ?? ""
            guard !value.contains("\u{0}") else {
                throw WidgetCommandError.refused("source.with.\(key) holds a NUL byte")
            }
            args += ["--\(key)", value]
        }
        return .packageCommand(package: parts.package, command: parts.command, args: args)
    }

    /// `devmachine run` as the CLI plan's Appendix B fixes it: `--machine`
    /// before `run`, `--workspace` after it, never both. A shell line goes
    /// through `--argv` as `env NAME=value … /bin/sh -c <line>`: each pair is
    /// one word, and the explicit `/bin/sh` keeps a fish login safe.
    public static func remote(_ command: TargetCommand, target: WidgetTarget, cli: CLIInvocationContext) -> ProcessInvocation? {
        let head: [String]
        switch target {
        case .local: return nil
        case let .machine(name): head = ["--machine", name, "run", "--no-log"]
        case let .workspace(name): head = ["run", "--workspace", name, "--no-log"]
        }
        let tail: [String]
        switch command {
        case let .argv(words):
            tail = ["--argv", "--"] + words
        case let .shell(line, environment):
            let pairs = environment.keys.sorted().map { "\($0)=\(environment[$0] ?? "")" }
            tail = ["--argv", "--", env] + pairs + [shell, "-c", line]
        case let .packageScript(package, script, args):
            tail = ["--package", package, "--script", script, "--"] + args
        case let .packageCommand(package, command, args):
            tail = ["--package", package, "--", command] + args
        }
        return ProcessInvocation(executable: cli.executable, arguments: head + tail, environment: cli.environment)
    }

    /// A program name is found on the PATH here and started directly, never
    /// through `env`, which would read a value-like name as an option.
    public static func local(
        _ command: TargetCommand, environment: [String: String], home: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> ProcessInvocation? {
        var variables = environment.filter { !$0.key.hasPrefix("DM_INPUT_") && !$0.key.hasPrefix("DM_CONTEXT_") }
        variables["PATH"] = LocalPATH.value(inherited: environment["PATH"], home: home)
        switch command {
        case let .argv(words):
            guard let first = words.first, !first.isEmpty,
                  let executable = first.contains("/")
                      ? first : find(first, path: variables["PATH"] ?? "", isExecutable: isExecutable)
            else { return nil }
            return ProcessInvocation(
                executable: executable, arguments: Array(words.dropFirst()), environment: variables, currentDirectory: home)
        case let .shell(line, values):
            variables.merge(values) { _, value in value }
            return ProcessInvocation(executable: shell, arguments: ["-c", line], environment: variables, currentDirectory: home)
        case .packageScript, .packageCommand:
            return nil
        }
    }

    private static func find(_ program: String, path: String, isExecutable: (String) -> Bool) -> String? {
        path.split(separator: ":").lazy.map { "\($0)/\(program)" }.first(where: isExecutable)
    }
}

