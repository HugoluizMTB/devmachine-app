import Foundation

public protocol CommandRunner: Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String

    /// Feeds `input` to the command's stdin. Used to write a file on the other
    /// side of an ssh connection without a second tool. `onBytesWritten` is
    /// called with the running total, so a caller can show real progress.
    func run(
        executable: String, args: [String], environment: [String: String]?, input: Data,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> String
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32)
    func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32)
    /// Hands each stderr line to `onStderrLine` while the command runs, for
    /// one that reports its own progress there. The result still holds all
    /// of stderr.
    func runCapturing(
        executable: String, args: [String], environment: [String: String]?,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) throws -> (stdout: String, stderr: String, exitCode: Int32)
}

public extension CommandRunner {
    /// Fakes in tests do not care about stdin.
    func run(
        executable: String, args: [String], environment: [String: String]?, input: Data,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> String {
        onBytesWritten?(input.count)
        return try run(executable: executable, args: args, environment: environment)
    }

    // Default for conformers that don't need stderr/exit-code detail (e.g.
    // test fakes): treat it as an always-successful capture of `run`'s output.
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        let stdout = try run(executable: executable, args: args, environment: environment)
        return (stdout, "", 0)
    }

    func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let input else {
            return try runCapturing(executable: executable, args: args, environment: environment)
        }
        let stdout = try run(
            executable: executable, args: args, environment: environment, input: input,
            onBytesWritten: onBytesWritten)
        return (stdout, "", 0)
    }

    /// Fakes answer at once, so their lines come after the fact.
    func runCapturing(
        executable: String, args: [String], environment: [String: String]?,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let result = try runCapturing(executable: executable, args: args, environment: environment)
        result.stderr.split(separator: "\n").forEach { onStderrLine(String($0)) }
        return result
    }
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    // Returns stdout regardless of exit code — callers that only care about
    // output (SessionStore/ContextStore/RemoteService) treat a nonzero exit
    // with usable stdout as a normal result (e.g. `tmux list-sessions`
    // exiting 1 with no server running, which SessionStore reads as "no
    // sessions", not "workspace offline"). Only a launch failure throws.
    public func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    public func run(
        executable: String, args: [String], environment: [String: String]?, input: Data,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> String {
        try runCapturing(
            executable: executable, args: args, environment: environment, input: input,
            onBytesWritten: onBytesWritten
        ).stdout
    }

    public func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        try runCapturing(
            executable: executable, args: args, environment: environment, input: nil,
            onBytesWritten: nil)
    }

    public func runCapturing(
        executable: String, args: [String], environment: [String: String]?,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try capture(
            executable: executable, args: args, environment: environment, input: nil,
            onBytesWritten: nil, onStderrLine: onStderrLine)
    }

    public func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try capture(
            executable: executable, args: args, environment: environment, input: input,
            onBytesWritten: onBytesWritten, onStderrLine: nil)
    }

    private func capture(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?, onStderrLine: (@Sendable (String) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        // Under XCTest a real ssh must never run: `~/.ssh/config` maps every
        // `*-devmachine` alias to the real host, so a fixture alias such as
        // `acme-devmachine` would log in as the Mac user and get the Mac banned
        // by fail2ban. Tests inject a fake runner; this is the safety net.
        if ["/ssh", "/mosh", "/mosh-client", "/scp"].contains(where: { executable.hasSuffix($0) }),
           NSClassFromString("XCTestCase") != nil {
            throw ProcessRunnerError.remoteCommandUnderTest(executable)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let environment { process.environment = environment }
        let inPipe = input.map { _ in Pipe() }
        process.standardInput = inPipe ?? FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        // Write stdin on its own thread and close it: a file bigger than the
        // pipe buffer would block here while the child waits on output we have
        // not started reading yet.
        if let inPipe, let input {
            let handle = inPipe.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                // In chunks, so progress is reported as the far side drains the
                // pipe rather than all at once when the write returns.
                var written = 0
                while written < input.count {
                    let end = min(written + 64 * 1024, input.count)
                    handle.write(input[written..<end])
                    written = end
                    onBytesWritten?(written)
                }
                try? handle.close()
            }
        }
        // Read BEFORE waiting: if the pipe buffer fills, waiting first
        // deadlocks the child (blocked writing) against us (blocked waiting).
        // Drain both pipes concurrently: reading one to EOF before the other
        // would deadlock if the child fills the second pipe's buffer while
        // blocked, since its EOF never comes until it exits.
        let errBox = DataBox()
        let errHandle = err.fileHandleForReading
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = Self.drain(errHandle, onLine: onStderrLine)
            drain.leave()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        drain.wait()
        process.waitUntilExit()

        return (
            String(data: data, encoding: .utf8) ?? "",
            String(data: errBox.data, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}

extension ProcessRunner {
    /// Reads to the end, in whatever pieces the pipe gives, cutting lines as
    /// they complete; a last line with no newline still counts.
    fileprivate static func drain(_ handle: FileHandle, onLine: (@Sendable (String) -> Void)?) -> Data {
        guard let onLine else { return handle.readDataToEndOfFile() }
        var all = Data()
        var pending = Data()
        while case let chunk = handle.availableData, !chunk.isEmpty {
            all.append(chunk)
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                onLine(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
        if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
        return all
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

public enum ProcessRunnerError: Error, Equatable {
    case remoteCommandUnderTest(String)
}
