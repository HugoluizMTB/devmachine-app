import Foundation
import XCTest
import DevmachineCore

// Holds every `run` until `release()` is called, so a test can look at what
// happens while a command is still in flight. Whatever is still held when a
// test ends is let go: a held `run` keeps one of Swift's cooperative threads,
// and a CI runner has only as many as it has cores, so three forgotten ones
// stopped every later `Task.detached` in the suite.
final class BlockingRunner: CommandRunner, @unchecked Sendable {
    private static let live = LiveBlockingRunners()

    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private var isOpen = false
    private let output: String

    init(output: String) {
        self.output = output
        Self.live.add(self)
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        calls += 1
        let open = isOpen
        lock.unlock()
        if !open { gate.wait() }
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

    fileprivate func open() {
        lock.lock()
        isOpen = true
        let held = calls
        lock.unlock()
        for _ in 0..<held { gate.signal() }
    }
}

private final class LiveBlockingRunners: NSObject, XCTestObservation, @unchecked Sendable {
    private let lock = NSLock()
    private let runners = NSHashTable<BlockingRunner>.weakObjects()

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func add(_ runner: BlockingRunner) {
        lock.lock()
        runners.add(runner)
        lock.unlock()
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        lock.lock()
        let all = runners.allObjects
        runners.removeAllObjects()
        lock.unlock()
        all.forEach { $0.open() }
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
