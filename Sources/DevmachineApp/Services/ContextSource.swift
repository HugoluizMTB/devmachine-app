import Foundation
import DevmachineCore

protocol ContextSource: Sendable {
    func context(for target: CommandTarget, settings: AppSettings) throws -> ContextState?
}

/// Resolves a value once and reuses it for the rest of the app's run. A
/// throwing resolution is not cached, so the next call tries again.
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

struct CLIContextSource: ContextSource {
    private let cli: @Sendable () throws -> DevmachineCLI
    private let selfMachine: SelfMachineCache
    private let nativeEngine: NativeContextEngine

    init(
        cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() },
        selfMachine: SelfMachineCache = SelfMachineCache(),
        nativeEngine: NativeContextEngine = NativeContextEngine()
    ) {
        self.cli = cli
        self.selfMachine = selfMachine
        self.nativeEngine = nativeEngine
    }

    func context(for target: CommandTarget, settings: AppSettings) throws -> ContextState? {
        switch target {
        case let .remote(alias, session):
            // Remote workspaces still go through the CLI's own devmachine-infer
            // package call over ssh — only the local machine runs in-process.
            let output = try cli().context(
                workspace: workspaceName(for: alias, settings: settings), session: session
            )
            return try JSONDecoder().decode(ContextState.self, from: Data(output.utf8))
        case let .local(_, path):
            // Still gated on this Mac being a registered `self:true` machine,
            // same as the package path was — a local session with no such
            // machine shows no context panel either way.
            guard try selfMachine.name(cli: cli) != nil else { return nil }
            let result = nativeEngine.buildContext(cwd: (path as NSString).expandingTildeInPath)
            let data = try JSONEncoder().encode(result)
            return try JSONDecoder().decode(ContextState.self, from: data)
        }
    }

    /// The sidebar's alias is the workspace's detected ssh `Host` name
    /// (`CLIWorkspaceSource`, from `settings.hostAlias(forWorkspace:)`); this
    /// undoes that to hand the CLI the name it knows the workspace by.
    private func workspaceName(for alias: String, settings: AppSettings) -> String {
        settings.workspaceName(forAlias: alias)
    }
}
