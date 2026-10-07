import Foundation

/// A package's own command feeding a widget: always `devmachine run
/// --package` on a machine or workspace, read as one JSON object.
public struct PackageProviderRunner: SourceRunner {
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
        guard case let .packageProvider(provider) = try SourceFailure.refusing({
            try request.source.resolved(context: request.context)
        }) else { throw SourceError.cannotStart("not a package provider source") }
        guard provider.target != .local else {
            throw SourceError.refused("a package provider runs on a machine or workspace")
        }
        let command = try SourceFailure.refusing { try ArgvBuilder.packageProvider(provider) }
        let (invocation, remote) = try TargetInvoker.invocation(command, on: provider.target, environment: environment)
        let data = try await ProcessCollector.collect(
            invocation, remote: remote, timeout: provider.timeout, launcher: launcher, sleep: sleep)
        let output = try SourceOutputs.parse(data, as: .json)
        try PackageProviderOutput.check(output, name: provider.name, returns: provider.returns)
        return .output(output)
    }
}

/// The contract's output rule: one JSON object holding every `returns`
/// field without `?`, not null. Types are left to the view's templates.
enum PackageProviderOutput {
    static func check(_ output: SourceOutput, name: String, returns: [String: String]) throws {
        guard case let .json(value) = output, let object = value.object else {
            throw SourceError.unreadable("\(name) printed JSON that is not one object")
        }
        let required = PackageProviderSpec(returns: returns, minEvery: "").requiredFields
        if let missing = required.first(where: { object[$0] == nil || object[$0] == .null }) {
            throw SourceError.unreadable("\(name) did not print \(missing)")
        }
    }
}
