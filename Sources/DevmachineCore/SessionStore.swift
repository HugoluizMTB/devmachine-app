import Foundation

public struct SessionStore: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner) {
        self.runner = runner
    }

    public func sessions(for workspace: Workspace) throws -> [TmuxSession] {
        let output = try runner.run(
            executable: "/usr/bin/ssh",
            args: RemoteCommands.sshBaseArgs(alias: workspace.alias) + [RemoteCommands.listSessions],
            environment: RemoteCommands.sshEnvironment()
        )
        return TmuxListParser.parse(output)
    }

    public func run(alias: String, command: String) throws -> String {
        try runner.run(
            executable: "/usr/bin/ssh",
            args: RemoteCommands.sshBaseArgs(alias: alias) + [command],
            environment: RemoteCommands.sshEnvironment()
        )
    }
}
