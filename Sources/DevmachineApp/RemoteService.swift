import Foundation
import DevmachineCore

struct RemoteService: Sendable {
    private let runner: CommandRunner

    init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    static func sshBaseArgs(alias: String) -> [String] {
        RemoteCommands.sshBaseArgs(alias: alias)
    }

    func run(alias: String, args: [String]) throws -> String {
        try runner.run(
            executable: "/usr/bin/ssh",
            args: RemoteService.sshBaseArgs(alias: alias) + Self.forHost(args, alias: alias),
            environment: RemoteCommands.sshEnvironment()
        )
    }

    func runCapturing(alias: String, args: [String]) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        try runner.runCapturing(
            executable: "/usr/bin/ssh",
            args: RemoteService.sshBaseArgs(alias: alias) + Self.forHost(args, alias: alias),
            environment: RemoteCommands.sshEnvironment()
        )
    }

    /// The last argument is the remote command; the machine's PATH prefix
    /// goes in front of it.
    static func forHost(_ args: [String], alias: String) -> [String] {
        guard let command = args.last else { return args }
        return args.dropLast() + [RemoteCommands.forHost(command, alias: alias)]
    }
}
