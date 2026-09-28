import Foundation
import DevmachineCore

struct PublishedSite: Codable, Equatable, Sendable {
    let host: String
    let port: Int
    let workspace: String?
}

struct CLIWorkspace: Codable, Equatable, Sendable {
    let name: String
    let machine: String
    let user: String
    let packages: [String]
}

private struct CLIWorkspaceList: Decodable {
    let workspaces: [CLIWorkspace]
}

struct CLIMachine: Decodable, Equatable, Sendable {
    let name: String
    let isSelf: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isSelf = "self"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
    }

    init(name: String, isSelf: Bool) {
        self.name = name
        self.isSelf = isSelf
    }
}

enum DevmachineCLIError: LocalizedError, Equatable {
    case commandFailed(String)
    case executableNotFound([String])

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            return detail.trimmingCharacters(in: .whitespacesAndNewlines)
        case .executableNotFound(let paths):
            return "Devmachine CLI was not found at \(paths.joined(separator: " or ")). Install it with `brew install mydevmachine/tap/devmachine`."
        }
    }
}

struct DevmachineCLI: Sendable {
    let executable: String
    let runner: any CommandRunner

    init(executable: String, runner: any CommandRunner = ProcessRunner()) {
        self.executable = executable
        self.runner = runner
    }

    static func resolve(
        injected: String? = nil,
        runner: any CommandRunner = ProcessRunner(),
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) throws -> DevmachineCLI {
        let paths = [injected].compactMap { $0 } + [
            "/opt/homebrew/bin/devmachine",
            "/usr/local/bin/devmachine",
        ]
        guard let executable = paths.first(where: exists) else {
            throw DevmachineCLIError.executableNotFound(paths)
        }
        return DevmachineCLI(executable: executable, runner: runner)
    }

    func expose(workspace: String, port: Int, host: String) throws {
        let result = try runner.runCapturing(
            executable: executable,
            args: [
                "expose", "add", workspace, String(port),
                "--host", host, "--publish",
            ],
            environment: Self.environment()
        )
        try requireSuccess(result)
    }

    func listExposures() throws -> [PublishedSite] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "expose", "list"],
            environment: Self.environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode([PublishedSite].self, from: Data(result.stdout.utf8))
    }

    func listWorkspaces() throws -> [CLIWorkspace] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "workspaces", "list"],
            environment: Self.environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIWorkspaceList.self, from: Data(result.stdout.utf8)).workspaces
    }

    func listMachines() throws -> [CLIMachine] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "machines", "list"],
            environment: Self.environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode([CLIMachine].self, from: Data(result.stdout.utf8))
    }

    /// The context engine, reached as `devmachine-app`'s `context` entrypoint.
    /// A workspace session runs it over the CLI's own ssh, as that workspace's
    /// account.
    func context(workspace: String, session: String) throws -> String {
        let result = try runner.runCapturing(
            executable: executable,
            args: [
                "run", "--workspace", workspace, "--package", "devmachine-app",
                "--", "context", "--session", session,
            ],
            environment: Self.environment()
        )
        try requireSuccess(result)
        return result.stdout
    }

    /// The same engine, run locally by the CLI on the named self machine.
    func context(machine: String, project: String) throws -> String {
        let result = try runner.runCapturing(
            executable: executable,
            args: [
                "run", "--machine", machine, "--package", "devmachine-app",
                "--", "context", "--project", project,
            ],
            environment: Self.environment()
        )
        try requireSuccess(result)
        return result.stdout
    }

    // An app opened from the Dock inherits launchd's empty SSH agent, not the
    // shell's, and the CLI reaches every machine through whatever agent it gets.
    private static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_AUTH_SOCK"] = RemoteCommands.onePasswordSocketPath
        return environment
    }

    private func requireSuccess(_ result: (stdout: String, stderr: String, exitCode: Int32)) throws {
        guard result.exitCode == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DevmachineCLIError.commandFailed(detail.isEmpty ? "Devmachine CLI failed." : detail)
        }
    }
}
