import Foundation
import DevmachineCore

protocol WorkspaceSource: Sendable {
    func workspaces(suffix: String) throws -> [Workspace]
}

struct SSHConfigWorkspaceSource: WorkspaceSource {
    private let readConfig: @Sendable () throws -> String

    init(readConfig: @escaping @Sendable () throws -> String = {
        try String(contentsOfFile: NSHomeDirectory() + "/.ssh/config", encoding: .utf8)
    }) {
        self.readConfig = readConfig
    }

    func workspaces(suffix: String) throws -> [Workspace] {
        SSHConfigParser.parse(try readConfig(), suffix: suffix)
    }
}
