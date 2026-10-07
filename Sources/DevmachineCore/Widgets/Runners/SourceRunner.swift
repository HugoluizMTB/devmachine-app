import Foundation

/// One fetch of a widget: its source with templates still in it, the area's
/// real context they are filled with, and the approvals as they are now.
public struct SourceRunRequest: Equatable, Sendable {
    public let instanceID: String
    public let source: ResolvedSource
    public let context: [String: String]
    public let approvals: WidgetApprovals

    public init(instanceID: String, source: ResolvedSource, context: [String: String] = [:], approvals: WidgetApprovals = WidgetApprovals()) {
        self.instanceID = instanceID
        self.source = source
        self.context = context
        self.approvals = approvals
    }

    public var tail: Int? { source.view.tail }
}

/// What a fetch gives back: the output, or the approval it waits for, with
/// the hash of exactly what it would have run.
public enum SourceRunResult: Equatable, Sendable {
    case output(SourceOutput)
    case needsApproval(ApprovalState)
}

/// Why a fetch gave no output, in the words a card shows.
public enum SourceError: Error, Equatable, Sendable {
    case exited(status: Int32, stderr: String)
    case neverRan(String)
    case timedOut(TimeInterval)
    case unreadable(String)
    case needsNewerCLI(String)
    case cannotStart(String)
    case refused(String)
    case http(String)

    public var title: String {
        switch self {
        case let .exited(status, _): return "It exited with \(status)"
        case .neverRan: return "It never ran"
        case let .timedOut(seconds): return "Timed out after \(GoDurationText.short(seconds))"
        case .unreadable: return "The output could not be read"
        case .needsNewerCLI: return "This needs a newer devmachine CLI"
        case .cannotStart: return "It could not start"
        case .refused: return "This widget cannot run"
        case .http: return "The page did not answer as expected"
        }
    }

    public var details: String {
        switch self {
        case let .exited(_, text), let .neverRan(text), let .unreadable(text), let .needsNewerCLI(text),
             let .cannotStart(text), let .refused(text), let .http(text):
            return text.isEmpty ? title : text
        case .timedOut: return title
        }
    }
}

/// Fetches one kind of source; every fetch checks its approval first.
public protocol SourceRunner: Sendable {
    func fetch(_ request: SourceRunRequest) async throws -> SourceRunResult
}

public typealias SourceSleep = @Sendable (TimeInterval) async throws -> Void
public let defaultSourceSleep: SourceSleep = { try await Task.sleep(for: .seconds($0)) }

/// The CLI, the Mac's environment and home, and how a program is found on
/// this Mac, so a test never reaches the real ones.
public struct SourceRunEnvironment: Sendable {
    public var cli: @Sendable () throws -> CLIInvocationContext
    public var localEnvironment: [String: String]
    public var home: String
    public var isExecutable: @Sendable (String) -> Bool

    public init(
        cli: @escaping @Sendable () throws -> CLIInvocationContext, localEnvironment: [String: String], home: String,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.cli = cli
        self.localEnvironment = localEnvironment
        self.home = home
        self.isExecutable = isExecutable
    }
}

/// Runs before anything else in a fetch: a source that needs approval runs
/// only when the hash of what it would run now, with this context, is allowed.
public enum SourceApprovalGate {
    public static func blocked(_ request: SourceRunRequest) throws -> ApprovalState? {
        guard request.source.needsApproval else { return nil }
        let hash = try SourceFailure.refusing { try ApprovalSubject.hash(for: request.source, context: request.context) }
        let state = request.approvals.state(needsApproval: true, hash: hash)
        return state.canRun ? nil : state
    }
}

enum SourceFailure {
    static func refusing<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as WidgetCommandError {
            throw SourceError.refused(error.localizedDescription)
        }
    }
}

/// Where a built command runs: here as its own process, or through
/// `devmachine run` (Appendix B) on a machine or workspace.
public enum TargetInvoker {
    public static func invocation(
        _ command: TargetCommand, on target: WidgetTarget, environment: SourceRunEnvironment
    ) throws -> (invocation: ProcessInvocation, remote: Bool) {
        switch target {
        case .local: return (try local(command, environment: environment), false)
        case let .machine(name), let .workspace(name):
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SourceError.cannotStart("the widget's target names no machine or workspace here")
            }
        }
        let cli: CLIInvocationContext
        do {
            cli = try environment.cli()
        } catch let error as SourceError {
            throw error
        } catch {
            throw SourceError.cannotStart(error.localizedDescription)
        }
        guard let remote = ArgvBuilder.remote(command, target: target, cli: cli) else {
            throw SourceError.cannotStart("no target to run on")
        }
        return (remote, true)
    }

    private static func local(_ command: TargetCommand, environment: SourceRunEnvironment) throws -> ProcessInvocation {
        if case let .argv(words) = command, let program = words.first, program.contains("/"),
           !environment.isExecutable(program) {
            throw SourceError.cannotStart("\(program) is not an executable file")
        }
        guard let local = ArgvBuilder.local(
            command, environment: environment.localEnvironment, home: environment.home,
            isExecutable: environment.isExecutable)
        else {
            if case let .argv(words) = command, let program = words.first, !program.isEmpty {
                throw SourceError.cannotStart("\(program) was not found on this Mac")
            }
            throw SourceError.cannotStart("this Mac runs a package script from the package's own folder, and none is known")
        }
        return local
    }
}

/// Appendix B's exit codes: 255 means `devmachine run` never ran the
/// command (or lost or stopped it), and its last `error:` line says why.
public enum SourceExitMapping {
    public static func error(status: Int32, stderr: String, stdoutWasEmpty: Bool, remote: Bool) -> SourceError? {
        guard status != 0 else { return nil }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote {
            if status == 1, stdoutWasEmpty, trimmed.contains("unknown flag") { return .needsNewerCLI(trimmed) }
            if status == 255 { return .neverRan(lastErrorLine(trimmed) ?? (trimmed.isEmpty ? "devmachine could not run it" : trimmed)) }
        }
        return .exited(status: status, stderr: trimmed)
    }

    static func lastErrorLine(_ stderr: String) -> String? {
        stderr.split(separator: "\n").reversed().first { $0.hasPrefix("error: ") }.map { String($0.dropFirst("error: ".count)) }
    }
}

private final class CollectedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var process: (any RunningProcess)?
    private var overflowed = false
    private var timedOut = false

    func append(_ chunk: Data) {
        let stop: (any RunningProcess)? = lock.withLock {
            guard !overflowed else { return nil }
            data.append(chunk)
            guard data.count > OutputParser.maxBytes else { return nil }
            overflowed = true
            data = Data()
            return process
        }
        stop?.terminate()
    }

    func attach(_ running: any RunningProcess) {
        let stopNow = lock.withLock {
            process = running
            return overflowed
        }
        if stopNow { running.terminate() }
    }

    func markTimedOut() { lock.withLock { timedOut = true } }

    var bytes: Data { lock.withLock { data } }
    var didOverflow: Bool { lock.withLock { overflowed } }
    var didTimeOut: Bool { lock.withLock { timedOut } }
}

/// Runs one process to its end: stdout up to 1 MB, stopped by SIGTERM on a
/// timeout, a flood or a cancelled fetch, and its exit read as Appendix B says.
public enum ProcessCollector {
    public static func collect(
        _ invocation: ProcessInvocation, remote: Bool, timeout: TimeInterval, launcher: any ProcessLaunching,
        sleep: @escaping SourceSleep = defaultSourceSleep
    ) async throws -> Data {
        try Task.checkCancellation()
        let output = CollectedOutput()
        let process: any RunningProcess
        do {
            process = try launcher.launch(invocation) { output.append($0) }
        } catch {
            throw SourceError.cannotStart("\(invocation.executable): \(error.localizedDescription)")
        }
        output.attach(process)
        let timer = Task {
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            output.markTimedOut()
            process.terminate()
        }
        let exit = await withTaskCancellationHandler {
            await process.wait()
        } onCancel: {
            process.terminate()
        }
        timer.cancel()
        try Task.checkCancellation()
        if output.didTimeOut { throw SourceError.timedOut(timeout) }
        if output.didOverflow { throw SourceError.unreadable("it printed more than 1 MB") }
        let data = output.bytes
        if let error = SourceExitMapping.error(status: exit.status, stderr: exit.stderr, stdoutWasEmpty: data.isEmpty, remote: remote) {
            throw error
        }
        return data
    }
}

enum SourceOutputs {
    static func parse(_ data: Data, as mode: ParseMode) throws -> SourceOutput {
        do {
            return try OutputParser.parse(data, as: mode)
        } catch let error as OutputParseError {
            throw SourceError.unreadable(error.message)
        }
    }
}
