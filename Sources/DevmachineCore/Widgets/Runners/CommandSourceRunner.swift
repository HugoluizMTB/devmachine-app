import Foundation

/// A command or package script, built only by `ResolvedSource.command(context:)`
/// so its templates are filled once, with the same context the approval hashed.
public struct CommandSourceRunner: SourceRunner {
    let launcher: any ProcessLaunching
    let environment: SourceRunEnvironment
    let sleep: SourceSleep

    public init(launcher: any ProcessLaunching, environment: SourceRunEnvironment, sleep: @escaping SourceSleep = defaultSourceSleep) {
        self.launcher = launcher
        self.environment = environment
        self.sleep = sleep
    }

    public func fetch(_ request: SourceRunRequest) async throws -> SourceRunResult {
        if let blocked = try SourceApprovalGate.blocked(request) { return .needsApproval(blocked) }
        guard case let .command(command) = try SourceFailure.refusing({ try request.source.resolved(context: request.context) }),
              let words = try SourceFailure.refusing({ try request.source.command(context: request.context) })
        else { throw SourceError.cannotStart("not a command source") }
        if command.target == .local, command.script != nil, request.source.package != nil,
           (request.source.packagePath ?? "").isEmpty {
            throw SourceError.cannotStart("this Mac runs a package script from the package's own folder, and none is known")
        }
        let (invocation, remote) = try TargetInvoker.invocation(words, on: command.target, environment: environment)
        let data = try await ProcessCollector.collect(
            invocation, remote: remote, timeout: command.timeout, launcher: launcher, sleep: sleep)
        return .output(try SourceOutputs.parse(data, as: command.parse))
    }
}
