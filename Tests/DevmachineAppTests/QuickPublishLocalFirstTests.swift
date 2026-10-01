import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class FakePortStats: PortStatsSource {
    var states: [String: MachineStatsState] = [:]
    var fresh: StatsSnapshot?
    private(set) var freshCalls: [String] = []

    func state(for machine: String?) -> MachineStatsState? {
        machine.flatMap { states[$0] }
    }

    func freshSnapshot(_ machine: String, maxAge: TimeInterval) async -> StatsSnapshot? {
        freshCalls.append(machine)
        if let fresh {
            states[machine] = MachineStatsState(snapshot: fresh, refreshedAt: Date())
        }
        return states[machine]?.snapshot
    }
}

final class WorkspaceListCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func bump() { lock.lock(); calls += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
}

func portsSnapshot(_ ports: [Int], owner: String = "alice") -> StatsSnapshot {
    let list = ports.map { #"{"port": \#($0), "owner": "\#(owner)"}"# }.joined(separator: ",")
    return StatsParser.parse("""
    {
      "collected_at": "2026-09-29T16:23:11+00:00",
      "memory": {"total_bytes": 1, "used_bytes": 1, "available_bytes": 1},
      "swap": {"total_bytes": 0, "used_bytes": 0},
      "disk": {"path": "/", "used_bytes": 1, "available_bytes": 2, "used_percent": 10},
      "load": {"load1": 0.1, "load5": 0.1, "load15": 0.1},
      "docker": {"available": true, "containers": []},
      "users": [],
      "ports": [\(list)],
      "errors": []
    }
    """)!
}

@MainActor
final class QuickPublishLocalFirstTests: XCTestCase {
    private let alice = CLIWorkspace(name: "alice", machine: "box", user: "alice", packages: [])

    private func makeData(cache: DataCache, counter: WorkspaceListCounter, workspaces: [CLIWorkspace]? = nil) -> WorkspaceMachineData {
        let list = workspaces ?? [alice]
        return WorkspaceMachineData(
            cache: cache,
            listWorkspaces: { counter.bump(); return list },
            listExposures: { _ in ExposureListing(sites: [], warning: nil) })
    }

    func testPublishAPortOpensWithCachedPortsWithoutAwaitingAFetch() {
        let clock = CacheClock()
        let cache = DataCache(now: { clock.now })
        cache.put(MachineDataKeys.workspaces, [alice])
        let stats = FakePortStats()
        stats.states["box"] = MachineStatsState(snapshot: portsSnapshot([5173, 3000]), refreshedAt: clock.now)
        let counter = WorkspaceListCounter()
        let state = QuickPublishState(data: makeData(cache: cache, counter: counter), now: { clock.now })

        state.start(workspace: "alice", stats: stats)

        XCTAssertEqual(state.workspace, "alice")
        XCTAssertEqual(state.ports.map(\.port), [3000, 5173])
        XCTAssertFalse(state.isRefreshingPorts)
        XCTAssertEqual(counter.count, 0)
        XCTAssertTrue(stats.freshCalls.isEmpty)
    }

    func testOldPortsShowAtOnceThenTheFreshOnesArrive() async throws {
        let clock = CacheClock()
        let cache = DataCache(now: { clock.now })
        cache.put(MachineDataKeys.workspaces, [alice])
        let stats = FakePortStats()
        stats.states["box"] = MachineStatsState(snapshot: portsSnapshot([3000]), refreshedAt: clock.now)
        stats.fresh = portsSnapshot([3000, 8080])
        clock.advance(120)
        let state = QuickPublishState(data: makeData(cache: cache, counter: WorkspaceListCounter()), now: { clock.now })

        state.start(workspace: "alice", stats: stats)

        XCTAssertEqual(state.workspace, "alice")
        XCTAssertEqual(state.ports.map(\.port), [3000])
        XCTAssertTrue(state.isRefreshingPorts)
        try await eventuallyTrue { !state.isRefreshingPorts }
        XCTAssertEqual(state.ports.map(\.port), [3000, 8080])
        XCTAssertEqual(stats.freshCalls, ["box"])
    }

    func testWithNothingCachedTheSheetStillOpensAtOnce() async throws {
        let cache = DataCache()
        let stats = FakePortStats()
        stats.fresh = portsSnapshot([4321])
        let counter = WorkspaceListCounter()
        let state = QuickPublishState(data: makeData(cache: cache, counter: counter))

        state.start(workspace: "alice", stats: stats)

        XCTAssertEqual(state.workspace, "alice")
        XCTAssertTrue(state.ports.isEmpty)
        try await eventuallyTrue { !state.isRefreshingPorts }
        XCTAssertEqual(state.ports.map(\.port), [4321])
        XCTAssertEqual(counter.count, 1)
    }

    func testWarmingASessionsWorkspaceFillsWhatPublishAPortReads() async throws {
        let cache = DataCache()
        let stats = FakePortStats()
        stats.fresh = portsSnapshot([3000])
        let counter = WorkspaceListCounter()
        let data = makeData(cache: cache, counter: counter)

        await data.warm(workspace: "alice", stats: stats)

        XCTAssertNotNil(cache.cached(MachineDataKeys.workspaces))
        XCTAssertNotNil(cache.cached(MachineDataKeys.sites("box")))
        XCTAssertEqual(data.cachedPorts(workspace: "alice", stats: stats)?.ports.map(\.port), [3000])
    }

    func testWarmingTwiceAsksTheCLIOnce() async {
        let cache = DataCache()
        let stats = FakePortStats()
        let counter = WorkspaceListCounter()
        let data = makeData(cache: cache, counter: counter)

        await data.warm(workspace: "alice", stats: stats)
        await data.warm(workspace: "alice", stats: stats)

        XCTAssertEqual(counter.count, 1)
    }
}
