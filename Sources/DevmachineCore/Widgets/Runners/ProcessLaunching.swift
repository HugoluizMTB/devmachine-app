import Foundation

/// How a widget's process ended, and whether the app stopped it.
public struct ProcessExit: Equatable, Sendable {
    public let status: Int32
    public let stderr: String
    public let stoppedByCaller: Bool

    public init(status: Int32, stderr: String, stoppedByCaller: Bool) {
        self.status = status
        self.stderr = stderr
        self.stoppedByCaller = stoppedByCaller
    }
}

/// A started process the runner can stop and wait for without holding a thread.
public protocol RunningProcess: AnyObject, Sendable {
    func terminate()
    func wait() async -> ProcessExit
}

/// Starts a widget's process, so runners can be tested with a fake one.
public protocol ProcessLaunching: Sendable {
    func launch(_ invocation: ProcessInvocation, onStdout: @escaping @Sendable (Data) -> Void) throws -> any RunningProcess
}

public enum ProcessLaunchError: Error, Equatable {
    case remoteCommandUnderTest(String)
}

/// Spawns a widget's process with stdin at end of file, hands stdout over
/// as it comes, keeps the first 16 KB of stderr, and stops it with SIGTERM,
/// then SIGKILL when it is still running after the grace.
public struct FoundationProcessLauncher: ProcessLaunching {
    public static let defaultKillGrace: TimeInterval = 5

    let killGrace: TimeInterval

    public init(killGrace: TimeInterval = FoundationProcessLauncher.defaultKillGrace) {
        self.killGrace = killGrace
    }

    public func launch(_ invocation: ProcessInvocation, onStdout: @escaping @Sendable (Data) -> Void) throws -> any RunningProcess {
        try LaunchedProcess(invocation, killGrace: killGrace, onStdout: onStdout)
    }
}

final class LaunchedProcess: RunningProcess, @unchecked Sendable {
    static let maxStderr = 16 * 1024
    private static let remoteTools: Set<String> = ["ssh", "mosh", "mosh-client", "scp"]

    private let process = Process()
    private let killGrace: TimeInterval
    private let lock = NSLock()
    private var stderrData = Data()
    private var stopped = false
    private var status: Int32?
    private var openPipes = 2
    private var result: ProcessExit?
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []

    init(_ invocation: ProcessInvocation, killGrace: TimeInterval, onStdout: @escaping @Sendable (Data) -> Void) throws {
        // Under XCTest a real ssh must never run: ~/.ssh/config maps fixture
        // aliases to the real host (CLAUDE.md "Tests never spawn ssh").
        var names = [URL(fileURLWithPath: invocation.executable).lastPathComponent]
        if names[0] == "env", let first = invocation.arguments.first { names.append(URL(fileURLWithPath: first).lastPathComponent) }
        if NSClassFromString("XCTestCase") != nil, names.contains(where: Self.remoteTools.contains) {
            throw ProcessLaunchError.remoteCommandUnderTest(invocation.executable)
        }
        self.killGrace = killGrace
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        if let environment = invocation.environment { process.environment = environment }
        if let directory = invocation.currentDirectory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.pipeClosed()
            } else {
                onStdout(data)
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.pipeClosed()
            } else {
                self?.appendStderr(data)
            }
        }
        process.terminationHandler = { [weak self] finished in
            self?.terminated(finished.terminationStatus)
        }
        try process.run()
    }

    func terminate() {
        let running: Bool = lock.withLock {
            stopped = true
            return status == nil
        }
        guard running, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGrace) { [weak self] in
            guard let self, self.lock.withLock({ self.status == nil }) else { return }
            kill(pid, SIGKILL)
        }
    }

    func wait() async -> ProcessExit {
        await withCheckedContinuation { continuation in
            let done: ProcessExit? = lock.withLock {
                if let result { return result }
                waiters.append(continuation)
                return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }

    private func appendStderr(_ data: Data) {
        lock.withLock {
            guard stderrData.count < Self.maxStderr else { return }
            stderrData.append(data.prefix(Self.maxStderr - stderrData.count))
        }
    }

    private func pipeClosed() {
        lock.withLock { openPipes -= 1 }
        finishIfReady(force: false)
    }

    /// A child the process left behind can hold the pipes open for good, so
    /// the exit is reported at most a second after the process itself ended.
    private func terminated(_ code: Int32) {
        lock.withLock { status = code }
        finishIfReady(force: false)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.finishIfReady(force: true)
        }
    }

    private func finishIfReady(force: Bool) {
        let ready: (ProcessExit, [CheckedContinuation<ProcessExit, Never>])? = lock.withLock {
            guard result == nil, let status, force || openPipes <= 0 else { return nil }
            let exit = ProcessExit(
                status: status, stderr: String(decoding: stderrData, as: UTF8.self), stoppedByCaller: stopped)
            result = exit
            defer { waiters.removeAll() }
            return (exit, waiters)
        }
        guard let (exit, waiting) = ready else { return }
        waiting.forEach { $0.resume(returning: exit) }
    }
}
