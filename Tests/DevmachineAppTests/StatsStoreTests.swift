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
    var machinesListFails = false
    private let gate = DispatchSemaphore(value: 0)
    private var holdsFetches = false

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
            return machinesListFails ? ("", "config unreadable", 1) : (machinesJSON, "", 0)
        }
        if let machineIndex = args.firstIndex(of: "--machine"), args.count > machineIndex + 1 {
            let machine = args[machineIndex + 1]
            lock.lock()
            let holds = holdsFetches
            lock.unlock()
            if holds { gate.wait() }
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

    func statsCalls(for machine: String) -> Int {
        calls.filter { $0.contains("stats") && $0.contains(machine) }.count
    }

    func holdFetches() {
        lock.lock()
        holdsFetches = true
        lock.unlock()
    }

    func releaseFetches(count: Int) {
        lock.lock()
        holdsFetches = false
        lock.unlock()
        for _ in 0..<count { gate.signal() }
    }
}

@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_790_000_000)

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
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

private func cachedEntry(_ machine: String, load1: Double, collectedAt: Date, address: String? = nil) -> CachedMachineStats {
    CachedMachineStats(
        machine: machine, firstAddress: address, collectedAt: collectedAt,
        snapshot: StatsParser.parse(snapshotJSON(load1: load1))!)
}

@MainActor
final class StatsStoreTests: XCTestCase {
    /// Every test gets its own `UserDefaults` suite: `StatsMachineSelection`'s
    /// default is `.standard`, which persists on disk between test runs and
    /// would leak one test's selection into the next.
    private var isolatedSelection: StatsMachineSelection!
    private var cache: StatsCache!
    private var cacheDirectory: URL!
    private var clock: TestClock!

    override func setUp() async throws {
        try await super.setUp()
        let defaults = UserDefaults(suiteName: "StatsStoreTests.\(UUID().uuidString)")!
        isolatedSelection = StatsMachineSelection(defaults: defaults)
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatsStoreTests-\(UUID().uuidString)", isDirectory: true)
        cache = StatsCache(fileURL: cacheDirectory.appendingPathComponent("stats-cache.json"))
        clock = TestClock()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try await super.tearDown()
    }

    private func makeStore(
        cli: @escaping @Sendable () throws -> DevmachineCLI,
        selection: StatsMachineSelection? = nil
    ) -> StatsStore {
        let clock = self.clock!
        return StatsStore(
            cli: cli, selection: selection ?? isolatedSelection, cache: cache,
            policy: StatsPollPolicy(interval: 90, backoff: [90, 180, 300], stagger: 0),
            tickInterval: nil, now: { clock.now })
    }

    private func makeStore(_ runner: MultiMachineRunner) -> StatsStore {
        makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })
    }

    func testASingleNonSelfMachineShowsNoSwitcher() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box","hosts":["203.0.113.10"]}]"#,
            snapshotsByMachine: ["box": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.start()
        try await waitUntil { store.snapshot != nil }

        XCTAssertFalse(store.showsSwitcher)
        XCTAssertEqual(store.selectedMachine, "box")
    }

    func testSeveralNonSelfMachinesShowTheSwitcher() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"},{"name":"beta"}]"#,
            snapshotsByMachine: ["acme": (goodSnapshot, "", 0), "beta": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.start()
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

        store.start()
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

        store.start()
        try await waitUntil { store.state(for: "acme")?.snapshot != nil }
        XCTAssertEqual(store.snapshot?.load.load1, 1.1)

        store.select("beta")
        try await waitUntil { store.snapshot?.load.load1 == 2.2 }

        XCTAssertEqual(store.selectedMachine, "beta")
    }

    func testThePollerFetchesEveryMachineNamingItWithMachine() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"},{"name":"beta"},{"name":"gamma"}]"#,
            snapshotsByMachine: [
                "acme": (goodSnapshot, "", 0),
                "beta": (goodSnapshot, "", 0),
                "gamma": (goodSnapshot, "", 0),
            ])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.start()
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
        let firstLaunch = makeStore(
            cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }, selection: selection)

        firstLaunch.start()
        try await waitUntil { firstLaunch.machines.count == 2 }
        firstLaunch.select("beta")
        try await waitUntil { firstLaunch.state(for: "beta")?.snapshot != nil }

        let secondLaunch = makeStore(
            cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }, selection: selection)
        secondLaunch.start()
        try await waitUntil { secondLaunch.selectedMachine != nil }

        XCTAssertEqual(secondLaunch.selectedMachine, "beta")
    }

    func testAFailedRunSurfacesTheCLIsStderrAndKeepsTheLastGoodSnapshot() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box"}]"#,
            snapshotsByMachine: ["box": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.start()
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

        store.start()
        try await waitUntil { store.errorText != nil }

        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.refreshedAt)
    }
    func testTheSkeletonShowsUntilTheFirstSnapshotArrives() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box"}]"#,
            snapshotsByMachine: ["box": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })
        XCTAssertTrue(store.showsSkeleton)

        store.start()
        try await waitUntil { store.snapshot != nil }

        XCTAssertFalse(store.showsSkeleton)
    }

    func testAFailedFirstLoadShowsTheErrorNotTheSkeleton() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box"}]"#,
            snapshotsByMachine: ["box": ("", "ssh: connect to host box port 22: Connection refused", 1)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.start()
        try await waitUntil { store.errorText != nil }

        XCTAssertFalse(store.showsSkeleton)
    }

    func testARefreshAfterASnapshotNeverBringsTheSkeletonBack() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"box"}]"#,
            snapshotsByMachine: ["box": (goodSnapshot, "", 0)])
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })
        store.start()
        try await waitUntil { store.snapshot != nil }

        store.refresh()

        XCTAssertTrue(store.isLoading)
        XCTAssertFalse(store.showsSkeleton)
    }

    func testNoMachineShowsTheEmptyStateNotTheSkeleton() async throws {
        let runner = MultiMachineRunner(machinesJSON: #"[{"name":"self","self":true}]"#)
        let store = makeStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.start()
        try await waitUntil { store.hasLoadedMachines }

        XCTAssertFalse(store.showsSkeleton)
    }

    func testAnOverviewCardShowsItsSkeletonOnlyWhileItHasNothingToShow() {
        XCTAssertTrue(MachineStatsState(isLoading: true).showsSkeleton)
        XCTAssertFalse(MachineStatsState(isLoading: false).showsSkeleton)
        XCTAssertFalse(MachineStatsState(isLoading: true, errorText: "timeout").showsSkeleton)
    }

    func testTheLastGoodSnapshotIsWrittenToTheCache() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme","hosts":["203.0.113.10"]}]"#,
            snapshotsByMachine: ["acme": (snapshotJSON(load1: 3.3), "", 0)])
        let store = makeStore(runner)

        store.start()
        try await waitUntil { store.snapshot != nil }

        let cached = cache.load()
        XCTAssertEqual(cached.map(\.machine), ["acme"])
        XCTAssertEqual(cached.first?.firstAddress, "203.0.113.10")
        XCTAssertEqual(cached.first?.snapshot.load.load1, 3.3)
        XCTAssertEqual(cached.first?.collectedAt, clock.now)
    }

    func testAFailureNeverOverwritesTheCache() async throws {
        try cache.save([cachedEntry("acme", load1: 1.5, collectedAt: clock.now.addingTimeInterval(-600))])
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"self","self":true},{"name":"acme"}]"#,
            snapshotsByMachine: ["acme": ("", "ssh: connect to host acme port 22: Connection refused", 1)])
        let store = makeStore(runner)

        store.start()
        try await waitUntil { store.errorText != nil }

        XCTAssertEqual(store.snapshot?.load.load1, 1.5)
        XCTAssertEqual(cache.load().first?.snapshot.load.load1, 1.5)
    }

    func testTheCacheDrawsMachinesAndSnapshotsBeforeAnyMachineAnswers() throws {
        let collectedAt = clock.now.addingTimeInterval(-120)
        try cache.save([
            cachedEntry("acme", load1: 1.1, collectedAt: collectedAt, address: "203.0.113.10"),
            cachedEntry("beta", load1: 2.2, collectedAt: collectedAt),
        ])
        let runner = MultiMachineRunner(machinesJSON: #"[{"name":"acme"},{"name":"beta"}]"#)
        runner.holdFetches()
        let store = makeStore(runner)

        store.start()

        XCTAssertEqual(store.machines.map(\.name), ["acme", "beta"])
        XCTAssertEqual(store.machines.first?.firstAddress, "203.0.113.10")
        XCTAssertEqual(store.selectedMachine, "acme")
        XCTAssertEqual(store.snapshot?.load.load1, 1.1)
        XCTAssertEqual(store.refreshedAt, collectedAt)
        XCTAssertEqual(store.state(for: "beta")?.snapshot?.load.load1, 2.2)
        XCTAssertFalse(store.showsSkeleton)
        runner.releaseFetches(count: 2)
    }

    func testTheSkeletonShowsOnlyWithoutACache() throws {
        let runner = MultiMachineRunner(machinesJSON: #"[{"name":"acme"}]"#)
        runner.holdFetches()
        let empty = makeStore(runner)
        empty.start()
        XCTAssertTrue(empty.showsSkeleton)

        try cache.save([cachedEntry("acme", load1: 1, collectedAt: clock.now)])
        let cached = makeStore(runner)
        cached.start()
        XCTAssertFalse(cached.showsSkeleton)
        runner.releaseFetches(count: 2)
    }

    func testAFreshCacheIsNotFetchedAgainUntilTheIntervalPasses() async throws {
        try cache.save([cachedEntry("acme", load1: 1, collectedAt: clock.now.addingTimeInterval(-30))])
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#, snapshotsByMachine: ["acme": (goodSnapshot, "", 0)])
        let store = makeStore(runner)

        store.start()
        try await waitUntil { store.hasLoadedMachineList }
        store.refreshIfStale("acme")
        store.tick()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runner.statsCalls(for: "acme"), 0)

        clock.advance(60)
        store.tick()
        try await waitUntil { runner.statsCalls(for: "acme") == 1 }
    }

    func testOpeningStatsOnAnOldCacheRefreshesInTheBackgroundWithoutASkeleton() async throws {
        try cache.save([cachedEntry("acme", load1: 1, collectedAt: clock.now.addingTimeInterval(-600))])
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#, snapshotsByMachine: ["acme": (snapshotJSON(load1: 4.4), "", 0)])
        let store = makeStore(runner)

        store.start()
        XCTAssertFalse(store.showsSkeleton)
        try await waitUntil { store.snapshot?.load.load1 == 4.4 }
        XCTAssertEqual(store.refreshedAt, clock.now)
    }

    func testThePollerRefreshesEveryIntervalAfterASuccess() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#, snapshotsByMachine: ["acme": (goodSnapshot, "", 0)])
        let store = makeStore(runner)
        store.start()
        try await waitUntil { store.snapshot != nil && !store.isLoading }

        clock.advance(89)
        store.tick()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runner.statsCalls(for: "acme"), 1)

        clock.advance(1)
        store.tick()
        try await waitUntil { runner.statsCalls(for: "acme") == 2 }
    }

    func testThePollerBacksOffAfterFailures() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#,
            snapshotsByMachine: ["acme": ("", "ssh: connect to host acme port 22: Connection refused", 1)])
        let store = makeStore(runner)
        store.start()
        try await waitUntil { store.errorText != nil && !store.isLoading }

        clock.advance(90)
        store.tick()
        try await waitUntil { runner.statsCalls(for: "acme") == 2 && !store.isLoading }

        clock.advance(179)
        store.tick()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runner.statsCalls(for: "acme"), 2)

        clock.advance(1)
        store.tick()
        try await waitUntil { runner.statsCalls(for: "acme") == 3 }
    }

    func testOnlyOneFetchPerMachineIsInFlight() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#, snapshotsByMachine: ["acme": (goodSnapshot, "", 0)])
        runner.holdFetches()
        let store = makeStore(runner)
        store.start()
        try await waitUntil { runner.statsCalls(for: "acme") == 1 }

        store.refresh()
        clock.advance(1_000)
        store.tick()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(runner.statsCalls(for: "acme"), 1)
        runner.releaseFetches(count: 1)
        try await waitUntil { store.snapshot != nil }
    }

    func testAManualRefreshRunsAtOnceEvenDuringBackoff() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#,
            snapshotsByMachine: ["acme": ("", "ssh: connect to host acme port 22: Connection refused", 1)])
        let store = makeStore(runner)
        store.start()
        try await waitUntil { store.errorText != nil && !store.isLoading }

        runner.snapshotsByMachine["acme"] = (goodSnapshot, "", 0)
        store.refresh()

        try await waitUntil { store.snapshot != nil }
        XCTAssertNil(store.errorText)
    }

    func testSleepPausesThePollerAndWakeRefreshesEveryMachine() async throws {
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#, snapshotsByMachine: ["acme": (goodSnapshot, "", 0)])
        let store = makeStore(runner)
        store.start()
        try await waitUntil { store.snapshot != nil && !store.isLoading }

        store.handleSleep()
        clock.advance(600)
        store.tick()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runner.statsCalls(for: "acme"), 1)

        store.handleWake()
        try await waitUntil { runner.statsCalls(for: "acme") == 2 }
    }

    func testAMachineGoneFromTheConfigLeavesTheCache() async throws {
        try cache.save([
            cachedEntry("acme", load1: 1, collectedAt: clock.now),
            cachedEntry("gone", load1: 1, collectedAt: clock.now),
        ])
        let runner = MultiMachineRunner(
            machinesJSON: #"[{"name":"acme"}]"#, snapshotsByMachine: ["acme": (goodSnapshot, "", 0)])
        let store = makeStore(runner)

        store.start()
        try await waitUntil { store.hasLoadedMachineList }

        XCTAssertEqual(store.machines.map(\.name), ["acme"])
        XCTAssertNil(store.state(for: "gone"))
        XCTAssertEqual(cache.load().map(\.machine), ["acme"])
    }

    func testAMachineListThatFailsKeepsTheCachedMachines() async throws {
        try cache.save([cachedEntry("acme", load1: 1, collectedAt: clock.now)])
        let runner = MultiMachineRunner(machinesJSON: "")
        runner.machinesListFails = true
        let store = makeStore(runner)

        store.start()
        try await waitUntil { store.hasLoadedMachineList }

        XCTAssertEqual(store.machines.map(\.name), ["acme"])
        XCTAssertNotNil(store.snapshot)
    }

    func testOpeningAMachineFromHomeSelectsItsTab() throws {
        try cache.save([
            cachedEntry("acme", load1: 1, collectedAt: clock.now),
            cachedEntry("beta", load1: 2, collectedAt: clock.now),
        ])
        let runner = MultiMachineRunner(machinesJSON: #"[{"name":"acme"},{"name":"beta"}]"#)
        runner.holdFetches()
        let store = makeStore(runner)
        store.start()

        store.select("beta")

        XCTAssertEqual(store.selectedMachine, "beta")
        XCTAssertEqual(store.snapshot?.load.load1, 2)
        XCTAssertFalse(store.showsSkeleton)
        runner.releaseFetches(count: 2)
    }
}
