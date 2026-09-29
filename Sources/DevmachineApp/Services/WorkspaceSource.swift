import Foundation
import DevmachineCore

protocol WorkspaceSource: Sendable {
    /// `resolveAlias` maps a workspace's name to its ssh `Host` alias —
    /// `settings.hostAlias(forWorkspace:)`, which uses the detected map from
    /// `devmachine aliases` and falls back to the guessed suffix.
    func workspaces(resolveAlias: (String) -> String) throws -> [Workspace]
}

struct CLIWorkspaceSource: WorkspaceSource {
    private let cli: @Sendable () throws -> DevmachineCLI

    init(cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }) {
        self.cli = cli
    }

    func workspaces(resolveAlias: (String) -> String) -> [Workspace] {
        do {
            return try cli().listWorkspaces().map { Workspace(name: $0.name, alias: resolveAlias($0.name)) }
        } catch {
            PaneLog.log("workspace list failed: \(error)")
            return []
        }
    }
}
