import Foundation
import DevmachineCore

protocol WorkspaceSource: Sendable {
    func workspaces(suffix: String) throws -> [Workspace]
}

struct CLIWorkspaceSource: WorkspaceSource {
    private let cli: @Sendable () throws -> DevmachineCLI

    init(cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }) {
        self.cli = cli
    }

    func workspaces(suffix: String) -> [Workspace] {
        do {
            return try cli().listWorkspaces().map { Workspace(name: $0.name, alias: $0.name + suffix) }
        } catch {
            PaneLog.log("workspace list failed: \(error)")
            return []
        }
    }
}
