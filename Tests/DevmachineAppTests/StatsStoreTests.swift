import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class MachinesListThenNextResultRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    var nextResult: (stdout: String, stderr: String, exitCode: Int32)

    init(nextResult: (stdout: String, stderr: String, exitCode: Int32)) {
        self.nextResult = nextResult
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(args)
        lock.unlock()
        if args.contains("machines") {
            return (#"[{"name":"self","self":true},{"name":"box"}]"#, "", 0)
        }
        return nextResult
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("condition never became true")
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

private let goodSnapshot = """
{
  "collected_at": "2026-09-29T16:23:11+00:00",
  "memory": {"total_bytes": 33554432000, "used_bytes": 12345678000, "available_bytes": 20000000000},
  "swap": {"total_bytes": 0, "used_bytes": 0},
  "disk": {"path": "/", "used_bytes": 1, "available_bytes": 2, "used_percent": 10},
  "load": {"load1": 0.1, "load5": 0.1, "load15": 0.1},
  "docker": {"available": true, "containers": []},
  "users": [],
  "ports": [],
  "errors": []
}
"""

@MainActor
final class StatsStoreTests: XCTestCase {
    func testRefreshRunsTheSnapshotThroughTheDevmachineCLIAsTheNonSelfMachinesAdmin() async throws {
        let runner = MachinesListThenNextResultRunner(nextResult: (goodSnapshot, "", 0))
        let store = StatsStore(
            cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) },
            adminMachine: AdminMachineCache())

        store.refresh()
        try await waitUntil { store.snapshot != nil }

        XCTAssertEqual(store.errorText, nil)
        XCTAssertNotNil(store.refreshedAt)
        XCTAssertTrue(runner.calls.contains {
            $0 == ["run", "--machine", "box", "--package", "devmachine-app", "--", "stats"]
        })
    }

    func testAFailedRunSurfacesTheCLIsStderrAndKeepsTheLastGoodSnapshot() async throws {
        let runner = MachinesListThenNextResultRunner(nextResult: (goodSnapshot, "", 0))
        let store = StatsStore(
            cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) },
            adminMachine: AdminMachineCache())

        store.refresh()
        try await waitUntil { store.snapshot != nil }
        let refreshedAtAfterSuccess = store.refreshedAt

        runner.nextResult = ("", "ssh: connect to host box port 22: Connection refused", 1)
        store.refresh()
        try await waitUntil { store.errorText != nil }

        XCTAssertEqual(store.errorText, "ssh: connect to host box port 22: Connection refused")
        XCTAssertNotNil(store.snapshot)
        XCTAssertEqual(store.refreshedAt, refreshedAtAfterSuccess)
    }

    func testEmptyOutputIsAnErrorNeverAZeroSnapshotAndNeverSetsRefreshedAt() async throws {
        let runner = MachinesListThenNextResultRunner(nextResult: ("", "", 0))
        let store = StatsStore(
            cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) },
            adminMachine: AdminMachineCache())

        store.refresh()
        try await waitUntil { store.errorText != nil }

        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.refreshedAt)
    }
}
