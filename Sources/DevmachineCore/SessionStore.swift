import Foundation

public struct SessionStore: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner) {
        self.runner = runner
    }

    public func sessions(for workspace: Workspace) throws -> [TmuxSession] {
        let result = try runner.runCapturing(
            executable: "/usr/bin/ssh",
            args: RemoteCommands.sshBaseArgs(alias: workspace.alias) + [RemoteCommands.listSessions],
            environment: RemoteCommands.sshEnvironment()
        )
        if let failure = SSHFailure.classify(exitCode: result.exitCode, stderr: result.stderr) {
            throw SessionStoreError(failure: failure, stderr: result.stderr)
        }
        return TmuxListParser.parse(result.stdout)
    }

    public func run(alias: String, command: String) throws -> String {
        try runner.run(
            executable: "/usr/bin/ssh",
            args: RemoteCommands.sshBaseArgs(alias: alias) + [command],
            environment: RemoteCommands.sshEnvironment()
        )
    }
}

/// ssh itself failing (exit 255), as opposed to the remote command: the host
/// or the agent is down, and every denied auth counts toward a fail2ban ban.
public enum SSHFailure: Equatable, Sendable {
    case authDenied
    case unreachable

    public static func classify(exitCode: Int32, stderr: String) -> SSHFailure? {
        guard exitCode == 255 else { return nil }
        return stderr.contains("Permission denied") ? .authDenied : .unreachable
    }
}

public struct SessionStoreError: Error, Equatable {
    public let failure: SSHFailure
    public let stderr: String
}
