import Foundation
@testable import DevmachineCore

final class FakeProcess: RunningProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var result: ProcessExit?
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []
    private var terminated = false

    init(exit: ProcessExit?) {
        result = exit
    }

    func terminate() {
        lock.withLock { terminated = true }
        finish(ProcessExit(status: 255, stderr: "", stoppedByCaller: true))
    }

    func finish(_ exit: ProcessExit) {
        let waiting: [CheckedContinuation<ProcessExit, Never>] = lock.withLock {
            guard result == nil else { return [] }
            result = exit
            defer { waiters.removeAll() }
            return waiters
        }
        waiting.forEach { $0.resume(returning: exit) }
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

    var isTerminated: Bool { lock.withLock { terminated } }
}

final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProcessInvocation] = []
    private var spawned: [FakeProcess] = []
    var stdout = Data()
    var status: Int32 = 0
    var stderr = ""
    var holds = false
    var launchError: Error?

    func launch(_ invocation: ProcessInvocation, onStdout: @escaping @Sendable (Data) -> Void) throws -> any RunningProcess {
        lock.withLock { recorded.append(invocation) }
        if let launchError { throw launchError }
        let process = FakeProcess(exit: holds ? nil : ProcessExit(status: status, stderr: stderr, stoppedByCaller: false))
        lock.withLock { spawned.append(process) }
        if !stdout.isEmpty { onStdout(stdout) }
        return process
    }

    var invocations: [ProcessInvocation] { lock.withLock { recorded } }
    var processes: [FakeProcess] { lock.withLock { spawned } }

    func releaseAll() {
        processes.forEach { $0.finish(ProcessExit(status: 0, stderr: "", stoppedByCaller: false)) }
    }
}

struct FakeHTTPClient: WidgetHTTPClient {
    var status = 200
    var body = Data()
    var error: Error?

    func get(_ url: URL, timeout: TimeInterval) async throws -> (status: Int, body: Data) {
        if let error { throw error }
        return (status, body)
    }
}

final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Date]

    init(_ times: [Date]) {
        self.times = times
    }

    func next() -> Date {
        lock.withLock { times.count > 1 ? times.removeFirst() : times[0] }
    }
}
