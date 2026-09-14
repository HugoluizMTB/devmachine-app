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
            args: RemoteService.sshBaseArgs(alias: alias) + args,
            environment: RemoteCommands.sshEnvironment()
        )
    }
}
