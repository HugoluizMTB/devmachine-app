import Foundation

protocol ContextSource: Sendable {
    func context(for target: CommandTarget) throws -> ContextState?
}

struct CommandContextSource: ContextSource {
    let host: HostRunner
    private let localEngineAvailable: @Sendable () -> Bool

    init(
        host: HostRunner = HostRunner(),
        localEngineAvailable: @escaping @Sendable () -> Bool = { LocalContext.isInstalled }
    ) {
        self.host = host
        self.localEngineAvailable = localEngineAvailable
    }

    func context(for target: CommandTarget) throws -> ContextState? {
        if target.isLocal && !localEngineAvailable() { return nil }
        let output = try host.runCapturingAnywhere(target, LocalContext.command(for: target)).stdout
        return try JSONDecoder().decode(ContextState.self, from: Data(output.utf8))
    }
}
