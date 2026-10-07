import DevmachineCore
import Foundation

private final class StreamInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var assembler = LineAssembler()
    private var pending: [String] = []

    func append(_ data: Data) { lock.withLock { pending += assembler.append(data) } }
    func finish() { lock.withLock { pending += assembler.flush() } }

    func take() -> [String] {
        lock.withLock {
            defer { pending.removeAll() }
            return pending
        }
    }
}

private final class RunningSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var process: (any RunningProcess)?

    func set(_ next: (any RunningProcess)?) { lock.withLock { process = next } }

    func take() -> (any RunningProcess)? {
        lock.withLock {
            defer { process = nil }
            return process
        }
    }
}

/// One `mode: stream` command: its last `keep` lines, delivered in 250 ms
/// batches (a hop per line froze the window for machine jobs), and a stop
/// that is SIGTERM and nothing else, whose exit is never shown as an error.
@MainActor
final class StreamSession {
    static let batchInterval: Duration = .milliseconds(250)
    static let defaultKeep = 200
    static let maximumKeep = 2000

    var onLines: ([String]) -> Void = { _ in }
    var onEnd: (SourceError?) -> Void = { _ in }

    private let launcher: any ProcessLaunching
    private var ring: LineRing
    private let inbox = StreamInbox()
    private let running = RunningSlot()
    private var flushTask: Task<Void, Never>?
    private var stopping = false

    init(launcher: any ProcessLaunching, keep: Int) {
        self.launcher = launcher
        ring = LineRing(capacity: Self.lineLimit(keep))
    }

    /// A session dropped without `stop()` would leave its `tail -f` running
    /// until the app quits. `isolated deinit` aborts at run time on the
    /// macOS 14 target, so the process sits in a lock-guarded slot.
    deinit {
        running.take()?.terminate()
    }

    static func lineLimit(_ keep: Int) -> Int {
        keep <= 0 ? defaultKeep : min(keep, maximumKeep)
    }

    var lines: [String] { ring.lines }

    func start(_ invocation: ProcessInvocation, remote: Bool) {
        let inbox = self.inbox
        let process: any RunningProcess
        do {
            process = try launcher.launch(invocation) { inbox.append($0) }
        } catch {
            onEnd(.cannotStart("\(invocation.executable): \(error.localizedDescription)"))
            return
        }
        running.set(process)
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.batchInterval)
                guard let self, !Task.isCancelled else { return }
                self.flushNow()
            }
        }
        Task { [weak self] in
            let exit = await process.wait()
            self?.ended(exit, remote: remote)
        }
    }

    func stop() {
        stopping = true
        flushTask?.cancel()
        running.take()?.terminate()
    }

    func flushNow() {
        let fresh = inbox.take()
        guard !fresh.isEmpty else { return }
        ring.append(contentsOf: fresh)
        onLines(ring.lines)
    }

    private func ended(_ exit: ProcessExit, remote: Bool) {
        running.set(nil)
        flushTask?.cancel()
        guard !stopping, !exit.stoppedByCaller else { return }
        inbox.finish()
        flushNow()
        onEnd(SourceExitMapping.error(status: exit.status, stderr: exit.stderr, stdoutWasEmpty: ring.lines.isEmpty, remote: remote))
    }
}
