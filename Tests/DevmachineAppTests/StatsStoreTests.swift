import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Routes `machines list` to a scripted list of non-self machines, and
/// `run --machine <name> --package devmachine-app -- stats` to a snapshot
/// keyed by that machine name — lets a test give each machine its own
/// numbers (or its own failure) instead of one shared canned response.
private final class MultiMachineRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    var machinesJSON: String
    var snapshotsByMachine: [String: (stdout: String, stderr: String, exitCode: Int32)]

    init(
        machinesJSON: String,
        snapshotsByMachine: [String: (stdout: String, stderr: String, exitCode: Int32)] = [:]
    ) {
        self.machinesJSON = machinesJSON
        self.snapshotsByMachine = snapshotsByMachine
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
            return (machinesJSON, "", 0)
        }
        if let machineIndex = args.firstIndex(of: "--machine"), args.count > machineIndex + 1 {
            let machine = args[machineIndex + 1]
            lock.lock()
            let result = snapshotsByMachine[machine]
            lock.unlock()
            return result ?? ("", "no stub for \(machine)", 1)
        }
        return ("", "unexpected args: \(args)", 1)
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

private func snapshotJSON(load1: Double) -> String {
    """
    {
      "collected_at": "2026-09-29T16:23:11+00:00",
      "memory": {"total_bytes": 33554432000, "used_bytes": 12345678000, "available_bytes": 20000000000},
      "swap": {"total_bytes": 0, "used_bytes": 0},
      "disk": {"path": "/", "used_bytes": 1, "available_bytes": 2, "used_percent": 10},
      "load": {"load1": \(load1), "load5": 0.1, "load15": 0.1},
      "docker": {"available": true, "containers": []},
      "users": [],
      "ports": [],
      "errors": []
    }
    """
}

private let goodSnapshot = snapshotJSON(load1: 0.1)

@MainActor
final class StatsStoreTests: XCTestCase {
    /// Every test gets its own `UserDefaults` suite: `StatsMachineSelection`'s
    /// default is `.standard`, which persists on disk between test runs and
    /// would leak one test's selection into the next.
    private var isolatedSelection: StatsMachineSelection!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "StatsStoreTests.\(UUID().uuidString)")!
        isolatedSelection = StatsMachineSelection(defaults: defaults)
    }

    private func makeStore(
        cli: @escaping @Sendable () throws -> DevmachineCLI,
        overviewConcurrencyLimit: Int = 3
    ) -> StatsStore {
        StatsStore(
            cli: cli, selection: isolatedSelection, overviewConcurrencyLimit: overviewConcurrencyLimit)
    }

    func testASingleNonSelfMachineShowsNoSwitcher() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box","hosts":["203.0.113.10"]}]"#,
            snapshotsByMachine: ["box": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.loadMachines()
        try await waitUntil { store.snapshot != nil }

        XCTAssertFalse(store.showsSwitcher)
        XCTAssertEqual(store.selectedMachine, "box")
    }

    func testSeveralNonSelfMachinesShowTheSwitcher() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"},{"name":"beta"}]"#,
            snapshotsByMachine: ["acme": (goodSnapshot, "", 0), "beta": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.loadMachines()
        try await waitUntil { store.machines.count == 2 }

        XCTAssertTrue(store.showsSwitcher)
        XCTAssertEqual(store.machines.map(\.name), ["acme", "beta"])
    }

    func testEachMachineKeepsItsOwnSnapshotAndErrorSeparate() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"},{"name":"beta"}]"#,
            snapshotsByMachine: [
                "acme": (goodSnapshot, "", 0),
                "beta": ("", "ssh: connect to host beta port 22: Connection refused", 1),
            ])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.loadMachines()
        try await waitUntil {
            store.state(for: "acme")?.snapshot != nil && store.state(for: "beta")?.errorText != nil
        }

        XCTAssertNotNil(store.state(for: "acme")?.snapshot)
        XCTAssertNil(store.state(for: "acme")?.errorText)
        XCTAssertNil(store.state(for: "beta")?.snapshot)
        XCTAssertEqual(
            store.state(for: "beta")?.errorText,
            "ssh: connect to host beta port 22: Connection refused")
    }

    func testSelectingAMachineSwitchesTheStoresPublishedSnapshot() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"},{"name":"beta"}]"#,
            snapshotsByMachine: [
                "acme": (snapshotJSON(load1: 1.1), "", 0),
                "beta": (snapshotJSON(load1: 2.2), "", 0),
            ])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.loadMachines()
        try await waitUntil { store.state(for: "acme")?.snapshot != nil }
        XCTAssertEqual(store.snapshot?.load.load1, 1.1)

        store.select("beta")
        try await waitUntil { store.snapshot?.load.load1 == 2.2 }

        XCTAssertEqual(store.selectedMachine, "beta")
    }

    func testOverviewFetchesEveryMachineConcurrently() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"},{"name":"beta"},{"name":"gamma"}]"#,
            snapshotsByMachine: [
                "acme": (goodSnapshot, "", 0),
                "beta": (goodSnapshot, "", 0),
                "gamma": (goodSnapshot, "", 0),
            ])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }, overviewConcurrencyLimit: 2)

        store.loadMachines()
        try await waitUntil {
            store.state(for: "acme")?.snapshot != nil
                && store.state(for: "beta")?.snapshot != nil
                && store.state(for: "gamma")?.snapshot != nil
        }

        XCTAssertTrue(runner.calls.contains {
            $0 == ["run", "--machine", "acme", "--package", "devmachine-app", "--", "stats"]
        })
        XCTAssertTrue(runner.calls.contains {
            $0 == ["run", "--machine", "beta", "--package", "devmachine-app", "--", "stats"]
        })
        XCTAssertTrue(runner.calls.contains {
            $0 == ["run", "--machine", "gamma", "--package", "devmachine-app", "--", "stats"]
        })
    }

    func testSelectionIsRememberedAcrossLaunches() async throws {
        let defaults = UserDefaults(suiteName: "StatsStoreTests.\(UUID().uuidString)")!
        let selection = StatsMachineSelection(defaults: defaults)
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"},{"name":"beta"}]"#,
            snapshotsByMachine: ["acme": (goodSnapshot, "", 0), "beta": (goodSnapshot, "", 0)])
        let firstLaunch = StatsStore(
            cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }, selection: selection)

        firstLaunch.loadMachines()
        try await waitUntil { firstLaunch.machines.count == 2 }
        firstLaunch.select("beta")
        try await waitUntil { firstLaunch.state(for: "beta")?.snapshot != nil }

        let secondLaunch = StatsStore(
            cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }, selection: selection)
        secondLaunch.loadMachines()
        try await waitUntil { secondLaunch.selectedMachine != nil }

        XCTAssertEqual(secondLaunch.selectedMachine, "beta")
    }

    func testAFailedRunSurfacesTheCLIsStderrAndKeepsTheLastGoodSnapshot() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box"}]"#,
            snapshotsByMachine: ["box": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.loadMachines()
        try await waitUntil { store.snapshot != nil }
        let refreshedAtAfterSuccess = store.refreshedAt

        runner.snapshotsByMachine["box"] = ("", "ssh: connect to host box port 22: Connection refused", 1)
        store.refresh()
        try await waitUntil { store.errorText != nil }

        XCTAssertEqual(store.errorText, "ssh: connect to host box port 22: Connection refused")
        XCTAssertNotNil(store.snapshot)
        XCTAssertEqual(store.refreshedAt, refreshedAtAfterSuccess)
    }

    func testEmptyOutputIsAnErrorNeverAZeroSnapshotAndNeverSetsRefreshedAt() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box"}]"#,
            snapshotsByMachine: ["box": ("", "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.loadMachines()
        try await waitUntil { store.errorText != nil }

        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.refreshedAt)
    }
}
