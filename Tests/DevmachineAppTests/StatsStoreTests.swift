import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Answers `machines list` with a fixed self+non-self pair and every other
/// call with whatever `nextResult` holds, recording the args it was given so
/// a test can check the exact `run --machine …` invocation.
private final class StatsRunner: CommandRunner, @unchecked Sendable {
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
@@MEM@@
33554432000 12345678000 20000000000
@@SWAP@@
0 0
@@DISK@@
1 2 10%
@@LOAD@@
0.1 0.1 0.1
@@DOCKER@@
@@USERS@@
"""

@MainActor
final class StatsStoreTests: XCTestCase {
    func testRefreshRunsTheSnapshotThroughTheDevmachineCLIAsTheNonSelfMachinesAdmin() async throws {
        let runner = StatsRunner(nextResult: (goodSnapshot, "", 0))
        let store = StatsStore { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }

        store.refresh()
        try await waitUntil { store.snapshot != nil }

        XCTAssertEqual(store.errorText, nil)
        XCTAssertNotNil(store.refreshedAt)
        XCTAssertTrue(runner.calls.contains {
            $0 == ["run", "--machine", "box", "--", RemoteCommands.statsSnapshot]
        })
    }

    func testAFailedRunSurfacesTheCLIsStderrAndKeepsTheLastGoodSnapshot() async throws {
        let runner = StatsRunner(nextResult: (goodSnapshot, "", 0))
        let store = StatsStore { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }

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
        let runner = StatsRunner(nextResult: ("", "", 0))
        let store = StatsStore { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }

        store.refresh()
        try await waitUntil { store.errorText != nil }

        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.refreshedAt)
    }
}
