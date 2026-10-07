import Foundation
import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

final class AppFakeProcess: RunningProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var result: ProcessExit?
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []
    private var stopped = false

    func terminate() {
        lock.withLock { stopped = true }
        finish(ProcessExit(status: 15, stderr: "", stoppedByCaller: true))
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

    var isTerminated: Bool { lock.withLock { stopped } }
}

final class AppFakeLauncher: ProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var spawned: [(process: AppFakeProcess, invocation: ProcessInvocation, stdout: @Sendable (Data) -> Void)] = []
    private var failure: Error?

    func failNextLaunches(with error: Error?) {
        lock.withLock { failure = error }
    }

    func launch(_ invocation: ProcessInvocation, onStdout: @escaping @Sendable (Data) -> Void) throws -> any RunningProcess {
        if let failure = lock.withLock({ failure }) { throw failure }
        let process = AppFakeProcess()
        lock.withLock { spawned.append((process, invocation, onStdout)) }
        return process
    }

    var processes: [AppFakeProcess] { lock.withLock { spawned.map(\.process) } }
    var invocations: [ProcessInvocation] { lock.withLock { spawned.map(\.invocation) } }

    func write(_ text: String, to index: Int = 0) {
        let sink = lock.withLock { spawned[index].stdout }
        sink(Data(text.utf8))
    }

    func releaseAll() {
        processes.forEach { $0.finish(ProcessExit(status: 0, stderr: "", stoppedByCaller: false)) }
    }
}

final class ScriptedSourceRunner: SourceRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<SourceRunResult, SourceError>]
    private var gated: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var received: [SourceRunRequest] = []
    private var cancelledFetches = 0

    init(_ answers: [Result<SourceRunResult, SourceError>] = [.success(.output(.text("ok")))], gated: Bool = false) {
        self.answers = answers
        self.gated = gated
    }

    func fetch(_ request: SourceRunRequest) async throws -> SourceRunResult {
        lock.withLock { received.append(request) }
        await withCheckedContinuation { continuation in
            let go = lock.withLock {
                guard gated else { return true }
                waiting.append(continuation)
                return false
            }
            if go { continuation.resume() }
        }
        if Task.isCancelled {
            lock.withLock { cancelledFetches += 1 }
            throw CancellationError()
        }
        if let blocked = try SourceApprovalGate.blocked(request) { return .needsApproval(blocked) }
        let answer = lock.withLock { answers.count > 1 ? answers.removeFirst() : answers[0] }
        return try answer.get()
    }

    var calls: Int { lock.withLock { received.count } }
    var cancelled: Int { lock.withLock { cancelledFetches } }
    var requests: [SourceRunRequest] { lock.withLock { received } }

    func release() {
        let all = lock.withLock {
            gated = false
            defer { waiting.removeAll() }
            return waiting
        }
        all.forEach { $0.resume() }
    }
}

final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}

@MainActor
func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<400 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("condition never held", file: file, line: line)
}
