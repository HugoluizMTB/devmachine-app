import Foundation

/// `claude -p -- <prompt>` / `codex exec --skip-git-repo-check -- <prompt>`,
/// one answer as markdown text. On this Mac the harness is found the way
/// Settings finds it, and its folder goes first on PATH so an npm-installed
/// CLI finds its `node`.
public struct PromptSourceRunner: SourceRunner {
    let launcher: any ProcessLaunching
    let environment: SourceRunEnvironment
    let locateHarness: @Sendable (PromptHarness) -> String?
    let sleep: SourceSleep

    public init(
        launcher: any ProcessLaunching, environment: SourceRunEnvironment,
        locateHarness: @escaping @Sendable (PromptHarness) -> String?, sleep: @escaping SourceSleep = defaultSourceSleep
    ) {
        self.launcher = launcher
        self.environment = environment
        self.locateHarness = locateHarness
        self.sleep = sleep
    }

    public func fetch(_ request: SourceRunRequest) async throws -> SourceRunResult {
        if let blocked = try SourceApprovalGate.blocked(request) { return .needsApproval(blocked) }
        guard case let .prompt(prompt) = try SourceFailure.refusing({ try request.source.resolved(context: request.context) }) else {
            throw SourceError.cannotStart("not a prompt source")
        }
        let words = ArgvBuilder.prompt(prompt)
        let invocation: ProcessInvocation
        let remote: Bool
        if prompt.target == .local {
            guard let path = locateHarness(prompt.harness) else {
                throw SourceError.cannotStart("\(prompt.harness.rawValue) was not found on this Mac")
            }
            guard case let .argv(argv) = words else { throw SourceError.cannotStart("no command for \(prompt.harness.rawValue)") }
            var local = try TargetInvoker.invocation(.argv([path] + argv.dropFirst()), on: .local, environment: environment).invocation
            let folder = URL(fileURLWithPath: path).deletingLastPathComponent().path
            let inherited = local.environment?["PATH"] ?? ""
            local.environment?["PATH"] = folder + ":" + inherited
            invocation = local
            remote = false
        } else {
            (invocation, remote) = try TargetInvoker.invocation(words, on: prompt.target, environment: environment)
        }
        let data = try await ProcessCollector.collect(invocation, remote: remote, timeout: prompt.timeout, launcher: launcher, sleep: sleep)
        return .output(try SourceOutputs.parse(data, as: .text))
    }
}
