import Foundation
import DevmachineCore

/// Where a panel's commands run. A remote session is read over ssh, in the
/// folder its tmux pane is in; a local one runs here, in the folder the
/// multiplexer reports.
enum CommandTarget: Equatable, Sendable {
    case remote(alias: String, session: String)
    case local(path: String)

    var key: String {
        switch self {
        case let .remote(alias, session): return "\(alias)/\(session)"
        case let .local(path): return "local:\(path)"
        }
    }

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}

/// Runs one shell command against either side, with the same result shape, so
/// a panel does not have to know which one it is reading.
struct HostRunner: Sendable {
    private let remote: RemoteService
    private let local: CommandRunner

    init(remote: RemoteService = RemoteService(), local: CommandRunner = ProcessRunner()) {
        self.remote = remote
        self.local = local
    }

    /// `command` runs in the target's own folder.
    func runCapturing(_ target: CommandTarget, _ command: String) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        switch target {
        case let .remote(alias, session):
            return try remote.runCapturing(
                alias: alias,
                args: [RemoteCommands.inSessionDirectory(session: session, command: command)])
        case let .local(path):
            return try local.runCapturing(
                executable: "/bin/sh",
                args: ["-c", RemoteCommands.inDirectory(path: path, command: command)],
                environment: LocalContext.environment())
        }
    }

    /// A command that names the folder it works on, so it does not need one.
    func runCapturingAnywhere(_ target: CommandTarget, _ command: String) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        switch target {
        case let .remote(alias, _):
            return try remote.runCapturing(alias: alias, args: [command])
        case .local:
            return try local.runCapturing(
                executable: "/bin/sh", args: ["-c", command],
                environment: LocalContext.environment())
        }
    }
}
