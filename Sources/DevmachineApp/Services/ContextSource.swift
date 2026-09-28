import Foundation
import DevmachineCore

protocol ContextSource: Sendable {
    func context(for target: CommandTarget, settings: AppSettings) throws -> ContextState?
}

/// One `machines list` answers "which machine is this Mac" for the rest of
/// the app's run: every local context request after the first reuses it. A
/// failed lookup is thrown and not kept, so the panel shows why and Retry
/// asks again.
final class SelfMachineCache: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false
    private var name: String?

    func name(cli: () throws -> DevmachineCLI) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if !resolved {
            name = try cli().listMachines().first { $0.isSelf }?.name
            resolved = true
        }
        return name
    }
}

struct CLIContextSource: ContextSource {
    private let cli: @Sendable () throws -> DevmachineCLI
    private let selfMachine: SelfMachineCache

    init(
        cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() },
        selfMachine: SelfMachineCache = SelfMachineCache()
    ) {
        self.cli = cli
        self.selfMachine = selfMachine
    }

    func context(for target: CommandTarget, settings: AppSettings) throws -> ContextState? {
        let output: String
        switch target {
        case let .remote(alias, session):
            output = try cli().context(workspace: workspaceName(for: alias, settings: settings), session: session)
        case let .local(_, path):
            guard let machine = try selfMachine.name(cli: cli) else { return nil }
            output = try cli().context(machine: machine, project: (path as NSString).expandingTildeInPath)
        }
        return try JSONDecoder().decode(ContextState.self, from: Data(output.utf8))
    }

    /// The app grows an alias by appending its ssh suffix to the workspace's
    /// own name (`CLIWorkspaceSource`); this undoes that to hand the CLI the
    /// name it knows the workspace by.
    private func workspaceName(for alias: String, settings: AppSettings) -> String {
        let suffix = settings.workspaceSuffix
        return alias.hasSuffix(suffix) ? String(alias.dropLast(suffix.count)) : alias
    }
}
