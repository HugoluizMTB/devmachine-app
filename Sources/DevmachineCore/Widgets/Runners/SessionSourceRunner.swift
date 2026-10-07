import Foundation

/// A session's screen, read only: tmux on a machine or workspace, the
/// bundled zmx on this Mac. Always argv, never a shell line.
public struct SessionSourceRunner: SourceRunner {
    public static let timeout: TimeInterval = 30
    public static let defaultTail = 200

    let launcher: any ProcessLaunching
    let environment: SourceRunEnvironment
    let zmxPath: @Sendable () -> String?
    let sleep: SourceSleep

    public init(
        launcher: any ProcessLaunching, environment: SourceRunEnvironment, zmxPath: @escaping @Sendable () -> String?,
        sleep: @escaping SourceSleep = defaultSourceSleep
    ) {
        self.launcher = launcher
        self.environment = environment
        self.zmxPath = zmxPath
        self.sleep = sleep
    }

    public func fetch(_ request: SourceRunRequest) async throws -> SourceRunResult {
        if let blocked = try SourceApprovalGate.blocked(request) { return .needsApproval(blocked) }
        guard case let .session(session) = try SourceFailure.refusing({ try request.source.resolved(context: request.context) }) else {
            throw SourceError.cannotStart("not a session source")
        }
        let invocation: ProcessInvocation
        let remote: Bool
        if session.target == .local {
            guard !session.session.hasPrefix("-") else {
                throw SourceError.refused("session \(session.session) would read as an option of zmx")
            }
            guard let zmx = zmxPath() else {
                throw SourceError.cannotStart("this build carries no zmx, so it cannot read a session on this Mac")
            }
            var local = try TargetInvoker.invocation(
                .argv([zmx, "history", session.session, "--vt"]), on: .local, environment: environment).invocation
            local.environment?["ZMX_DIR"] = Zmx.socketDirectory()
            local.environment?["HOME"] = environment.home
            invocation = local
            remote = false
        } else {
            (invocation, remote) = try TargetInvoker.invocation(
                ArgvBuilder.tmuxCapture(session: session.session), on: session.target, environment: environment)
        }
        let data = try await ProcessCollector.collect(invocation, remote: remote, timeout: Self.timeout, launcher: launcher, sleep: sleep)
        guard case let .ansi(screen) = try SourceOutputs.parse(data, as: .ansi) else { return .output(.ansi("")) }
        return .output(.ansi(TextTail.lines(of: screen, tail: request.tail ?? Self.defaultTail).joined(separator: "\n")))
    }
}
