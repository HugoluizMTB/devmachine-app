import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class FakeJobRunner: MachineJobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.withLock { _calls } }
    let script: @Sendable ([String], @Sendable (String) -> Void) async throws -> Int32

    init(script: @escaping @Sendable ([String], @Sendable (String) -> Void) async throws -> Int32 = { _, _ in 0 }) {
        self.script = script
    }

    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        lock.withLock { _calls.append(arguments) }
        return try await script(arguments, output)
    }
}

@MainActor
final class MachineJobCenterTests: XCTestCase {
    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition never held", file: file, line: line)
    }

    func testRequestSyncMergesIntoPendingCard() {
        let center = MachineJobCenter(runner: FakeJobRunner())
        let a = center.requestSync(SyncRequest(machine: "main", tags: ["docker"], reasons: ["Packages"]))
        let b = center.requestSync(SyncRequest(machine: "main", tags: ["node"], reasons: ["DNS"]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(center.jobs.count, 1)
        XCTAssertEqual(center.jobs[0].request?.tags, ["docker", "node"])
        XCTAssertEqual(center.jobs[0].phase, .pending)
    }

    func testStartTaggedRunsTheTaggedSync() async {
        let runner = FakeJobRunner { _, output in
            output("main: ok=3 changed=1 failed=0")
            return 0
        }
        let center = MachineJobCenter(runner: runner, cliVersion: { SemanticVersion(major: 0, minor: 7, patch: 30) })
        var outcome: MachineJobOutcome?
        let id = center.requestSync(SyncRequest(machine: "main", tags: ["docker"]), onFinish: { outcome = $0 })
        XCTAssertFalse(center.startsFull(id))
        center.start(id, full: false)
        await waitUntil { outcome != nil }
        XCTAssertEqual(runner.calls, [["sync", "--machine", "main", "--tags", "docker", "--yes"]])
        XCTAssertEqual(center.job(id)?.phase, .succeeded(SyncSummary(ok: 3, changed: 1, failed: 0)))
        XCTAssertEqual(outcome, .succeeded)
    }

    func testOldCLIStartsFull() {
        let center = MachineJobCenter(runner: FakeJobRunner(), cliVersion: { SemanticVersion(major: 0, minor: 7, patch: 20) })
        let id = center.requestSync(SyncRequest(machine: "main", tags: ["docker"]))
        XCTAssertTrue(center.startsFull(id))
    }

    func testFailureTakesTheCLIErrorLine() async {
        let runner = FakeJobRunner { _, output in
            output("error: machine main is unreachable")
            return 1
        }
        let center = MachineJobCenter(runner: runner)
        let id = center.run(MachineJobPlan(machine: "main", title: "Sync main", steps: [["sync", "--machine", "main", "--yes"]]))
        await waitUntil { if case .failed = center.job(id)?.phase { return true } else { return false } }
        XCTAssertEqual(center.job(id)?.phase, .failed(cause: "machine main is unreachable"))
        XCTAssertEqual(center.job(id)?.log.lines.first, "$ devmachine sync --machine main --yes")
    }

    func testStopsAtTheFirstFailedStep() async {
        let runner = FakeJobRunner { args, _ in args[0] == "first" ? 2 : 0 }
        let center = MachineJobCenter(runner: runner)
        let id = center.run(MachineJobPlan(machine: "main", title: "Two", steps: [["first"], ["second"]]))
        await waitUntil { if case .failed = center.job(id)?.phase { return true } else { return false } }
        XCTAssertEqual(runner.calls, [["first"]])
    }

    func testRequestWhileRunningAddsPendingAndQueuesOnStart() async {
        let gate = AsyncGate()
        let runner = FakeJobRunner { args, _ in
            if args == ["slow"] { await gate.wait() }
            return 0
        }
        let center = MachineJobCenter(runner: runner)
        let running = center.run(MachineJobPlan(machine: "main", title: "Slow", steps: [["slow"]]))
        await waitUntil { center.job(running)?.phase == .running(step: 0) }
        let pending = center.requestSync(SyncRequest(machine: "main", tags: ["docker"]))
        XCTAssertNotEqual(running, pending)
        center.start(pending, full: false)
        XCTAssertEqual(center.job(pending)?.phase, .queued)
        await gate.open()
        await waitUntil { if case .succeeded = center.job(pending)?.phase { return true } else { return false } }
        XCTAssertEqual(runner.calls.count, 2)
    }

    func testOtherMachinesRunInParallel() async {
        let gate = AsyncGate()
        let runner = FakeJobRunner { args, _ in
            if args == ["slow"] { await gate.wait() }
            return 0
        }
        let center = MachineJobCenter(runner: runner)
        _ = center.run(MachineJobPlan(machine: "main", title: "Slow", steps: [["slow"]]))
        let other = center.run(MachineJobPlan(machine: "dev", title: "Fast", steps: [["fast"]]))
        await waitUntil { if case .succeeded = center.job(other)?.phase { return true } else { return false } }
        await gate.open()
    }

    func testCancelRunningEndsCancelled() async {
        let runner = FakeJobRunner { _, _ in
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return 0
        }
        let center = MachineJobCenter(runner: runner)
        var outcome: MachineJobOutcome?
        let id = center.run(MachineJobPlan(machine: "main", title: "Long", steps: [["long"]]), onFinish: { outcome = $0 })
        await waitUntil { center.job(id)?.phase == .running(step: 0) }
        center.cancel(id)
        await waitUntil { outcome != nil }
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertNil(center.job(id))
    }

    func testCancelPendingRemovesIt() {
        let center = MachineJobCenter(runner: FakeJobRunner())
        let id = center.requestSync(SyncRequest(machine: "main"))
        center.cancel(id)
        XCTAssertTrue(center.jobs.isEmpty)
    }

    func testSuccessDismissesItselfUnlessExpanded() async {
        let center = MachineJobCenter(runner: FakeJobRunner(), successSeconds: 0.05)
        let quiet = center.run(MachineJobPlan(machine: "main", title: "A", steps: [["a"]]))
        let open = center.run(MachineJobPlan(machine: "dev", title: "B", steps: [["b"]]))
        center.toggleExpanded(open)
        await waitUntil { center.job(quiet) == nil }
        XCTAssertNotNil(center.job(open))
    }

    func testRetryRunsAgainWithAFreshLog() async {
        let attempts = Counter()
        let runner = FakeJobRunner { _, output in
            output("attempt")
            return attempts.next() == 1 ? 1 : 0
        }
        let center = MachineJobCenter(runner: runner)
        let id = center.run(MachineJobPlan(machine: "main", title: "A", steps: [["a"]]))
        await waitUntil { if case .failed = center.job(id)?.phase { return true } else { return false } }
        center.retry(id)
        await waitUntil { if case .succeeded = center.job(id)?.phase { return true } else { return false } }
        XCTAssertEqual(center.job(id)?.log.lines, ["$ devmachine a", "attempt"])
    }

    func testRetriedJobReportsEveryFinish() async {
        let attempts = Counter()
        let runner = FakeJobRunner { _, _ in attempts.next() == 1 ? 1 : 0 }
        let center = MachineJobCenter(runner: runner)
        var outcomes: [MachineJobOutcome] = []
        let id = center.run(MachineJobPlan(machine: "main", title: "A", steps: [["a"]]), onFinish: { outcomes.append($0) })
        await waitUntil { outcomes == [.failed] }
        center.retry(id)
        await waitUntil { outcomes.count == 2 }
        XCTAssertEqual(outcomes, [.failed, .succeeded])
    }

    func testDismissingAFailedJobReportsNothingMore() async {
        let center = MachineJobCenter(runner: FakeJobRunner { _, _ in 1 })
        var outcomes: [MachineJobOutcome] = []
        let id = center.run(MachineJobPlan(machine: "main", title: "A", steps: [["a"]]), onFinish: { outcomes.append($0) })
        await waitUntil { outcomes == [.failed] }
        center.dismiss(id)
        XCTAssertNil(center.job(id))
        XCTAssertEqual(outcomes, [.failed])
    }

    func testCollapsedSuccessGoesAway() async {
        let center = MachineJobCenter(runner: FakeJobRunner(), successSeconds: 0.05)
        let id = center.run(MachineJobPlan(machine: "main", title: "A", steps: [["a"]]))
        center.toggleExpanded(id)
        await waitUntil { if case .succeeded = center.job(id)?.phase { return true } else { return false } }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNotNil(center.job(id))
        center.toggleExpanded(id)
        await waitUntil { center.job(id) == nil }
    }

    func testCancelBetweenStepsNeverStartsTheNextStep() async {
        let gate = AsyncGate()
        let runner = FakeJobRunner { args, _ in
            if args == ["first"] { await gate.wait() }
            return 0
        }
        let center = MachineJobCenter(runner: runner)
        var outcome: MachineJobOutcome?
        let id = center.run(
            MachineJobPlan(machine: "main", title: "Two", steps: [["first"], ["second"]]), onFinish: { outcome = $0 })
        await waitUntil { runner.calls == [["first"]] }
        center.cancel(id)
        await gate.open()
        await waitUntil { outcome != nil }
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(runner.calls, [["first"]])
    }
}

private actor AsyncGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}
