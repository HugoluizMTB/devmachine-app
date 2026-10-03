import Foundation

/// Collects a process's lines off the main thread and hands them over in
/// order, one main-actor hop per batch: a hop per line, each carrying the
/// whole log, froze the window on a first sync.
final class JobOutputBuffer: @unchecked Sendable {
    private let deliver: @MainActor ([String]) -> Void
    private let lock = NSLock()
    private var pending: [String] = []
    private var scheduled = false

    init(deliver: @escaping @MainActor ([String]) -> Void) {
        self.deliver = deliver
    }

    func receive(_ line: String) {
        let schedule = lock.withLock {
            pending.append(line)
            guard !scheduled else { return false }
            scheduled = true
            return true
        }
        guard schedule else { return }
        Task { @MainActor [weak self] in self?.flushNow() }
    }

    @MainActor
    func flushNow() {
        let lines = lock.withLock {
            scheduled = false
            defer { pending = [] }
            return pending
        }
        guard !lines.isEmpty else { return }
        deliver(lines)
    }
}
