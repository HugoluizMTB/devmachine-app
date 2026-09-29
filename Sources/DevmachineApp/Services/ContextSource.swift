import Foundation
import DevmachineCore

protocol ContextSource: Sendable {
    func context(for target: CommandTarget, settings: AppSettings) throws -> ContextState?
}

/// Resolves a value once and reuses it for the rest of the app's run. A
/// throwing resolution is not cached, so the next call tries again — used by
/// `SelfMachineCache` and `AdminMachineCache`, which differ only in which
/// machine they ask `machines list` for.
private final class ResolvedOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false
    private var value: Value?

    func get(_ resolve: () throws -> Value) throws -> Value {
        lock.lock()
        defer { lock.unlock() }
        if !resolved {
            value = try resolve()
            resolved = true
        }
        return value!
    }
}

/// One `machines list` answers "which machine is this Mac" for the rest of
/// the app's run: every local context request after the first reuses it.
final class SelfMachineCache: @unchecked Sendable {
    private let cache = ResolvedOnce<String?>()

    func name(cli: () throws -> DevmachineCLI) throws -> String? {
        try cache.get { try cli().listMachines().first { $0.isSelf }?.name }
    }
}

/// The same idea, for the other direction: which machine an admin-level
/// command (stats, Caddy's own logs) runs on.
final class AdminMachineCache: @unchecked Sendable {
    private let cache = ResolvedOnce<String>()

    func name(cli: () throws -> DevmachineCLI) throws -> String {
        try cache.get { try cli().resolveAdminMachine() }
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
