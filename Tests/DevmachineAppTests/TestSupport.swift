import Foundation
import DevmachineCore

// Holds every `run` until `release()` is called, so a test can look at what
// happens while a command is still in flight.
final class BlockingRunner: CommandRunner, @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private let output: String

    init(output: String) {
        self.output = output
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        gate.wait()
        return output
    }

    func release() {
        gate.signal()
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func bump() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
