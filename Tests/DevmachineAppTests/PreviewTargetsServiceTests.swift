import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    let answer: ([String]) -> String

    init(answer: @escaping ([String]) -> String) {
        self.answer = answer
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.withLock { storedCalls.append([executable] + args) }
        return answer(args)
    }

    var calls: [[String]] { lock.withLock { storedCalls } }
}

private final class ExposureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var sites: [ExposedSite]

    init(_ sites: [ExposedSite]) { self.sites = sites }

    func list() -> ExposureListing {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return ExposureListing(sites: sites, warning: nil)
    }

    func set(_ sites: [ExposedSite]) { lock.withLock { self.sites = sites } }
    var count: Int { lock.withLock { calls } }
}

final class PreviewTargetsServiceTests: XCTestCase {
    func testThisMacListsWhatItListensOn() throws {
        let local = ScriptedRunner { _ in "p1\ncnode\nn*:5173\n" }
        let service = PreviewTargetsService(localRunner: local)

        let targets = try service.localTargets()

        XCTAssertEqual(targets.map(\.kind), [.port(5173)])
        XCTAssertEqual(local.calls.first?.first, "/usr/sbin/lsof")
    }
}

@MainActor
final class PreviewTargetsStoreTests: XCTestCase {
    private let acme = CLIWorkspace(name: "acme", machine: "main", user: "acme", packages: [])
    private let site = ExposedSite(host: "app.acme.example.com", port: 3000, workspace: "acme", status: .published)

    private func makeStore(cache: DataCache, exposures: ExposureCounter, workspaces: [CLIWorkspace]? = nil) -> PreviewTargetsStore {
        let list = workspaces ?? [acme]
        let data = WorkspaceMachineData(
            cache: cache, listWorkspaces: { list }, listExposures: { _ in exposures.list() })
        return PreviewTargetsStore(service: PreviewTargetsService(localRunner: ScriptedRunner { _ in "" }), data: data)
    }

    func testAWorkspaceDrawsFromTheCacheAndThePollersPortsWithoutAsking() {
        let cache = DataCache()
        cache.put(MachineDataKeys.workspaces, [acme])
        cache.put(MachineDataKeys.sites("main"), ExposureListing(sites: [site], warning: nil))
        let stats = FakePortStats()
        stats.states["main"] = MachineStatsState(snapshot: portsSnapshot([5173], owner: "acme"), refreshedAt: Date())
        let exposures = ExposureCounter([site])
        let store = makeStore(cache: cache, exposures: exposures)

        store.load(.workspace("acme"), stats: stats)

        guard case let .loaded(targets) = store.phase(for: .workspace("acme")) else { return XCTFail("not loaded") }
        XCTAssertEqual(targets.map(\.kind), [.site(host: "app.acme.example.com"), .port(5173)])
        XCTAssertFalse(store.isRefreshing(.workspace("acme")))
        XCTAssertEqual(exposures.count, 0)
        XCTAssertTrue(stats.freshCalls.isEmpty)
    }

    func testWithNothingCachedItLoadsThenShowsTheList() async throws {
        let stats = FakePortStats()
        stats.fresh = portsSnapshot([5173], owner: "acme")
        let exposures = ExposureCounter([site])
        let store = makeStore(cache: DataCache(), exposures: exposures)

        store.load(.workspace("acme"), stats: stats)
        XCTAssertEqual(store.phase(for: .workspace("acme")), .loading)

        try await eventuallyTrue { if case .loaded = store.phase(for: .workspace("acme")) { return true }; return false }
        guard case let .loaded(targets) = store.phase(for: .workspace("acme")) else { return XCTFail("not loaded") }
        XCTAssertEqual(targets.map(\.kind), [.site(host: "app.acme.example.com"), .port(5173)])
        XCTAssertEqual(exposures.count, 1)
    }

    func testAnUnknownWorkspaceFails() async throws {
        let store = makeStore(cache: DataCache(), exposures: ExposureCounter([]), workspaces: [])

        store.load(.workspace("beta"), stats: FakePortStats())

        try await eventuallyTrue { if case .failed = store.phase(for: .workspace("beta")) { return true }; return false }
    }

    func testANewListingInTheCacheReachesTheOpenPreviewAtOnce() {
        let cache = DataCache()
        cache.put(MachineDataKeys.workspaces, [acme])
        cache.put(MachineDataKeys.sites("main"), ExposureListing(sites: [], warning: nil))
        let stats = FakePortStats()
        stats.states["main"] = MachineStatsState(snapshot: portsSnapshot([]), refreshedAt: Date())
        let store = makeStore(cache: cache, exposures: ExposureCounter([]))
        store.load(.workspace("acme"), stats: stats)

        cache.put(MachineDataKeys.sites("main"), ExposureListing(sites: [site], warning: nil))

        guard case let .loaded(targets) = store.phase(for: .workspace("acme")) else { return XCTFail("not loaded") }
        XCTAssertEqual(targets.map(\.kind), [.site(host: "app.acme.example.com")])
    }

    func testRefreshReadsTheSitesAgainAndAsksThePollerForNewPorts() async throws {
        let cache = DataCache()
        cache.put(MachineDataKeys.workspaces, [acme])
        cache.put(MachineDataKeys.sites("main"), ExposureListing(sites: [], warning: nil))
        let stats = FakePortStats()
        stats.states["main"] = MachineStatsState(snapshot: portsSnapshot([]), refreshedAt: Date())
        let exposures = ExposureCounter([site])
        let store = makeStore(cache: cache, exposures: exposures)

        store.load(.workspace("acme"), stats: stats, force: true)

        try await eventuallyTrue { !store.isRefreshing(.workspace("acme")) }
        XCTAssertEqual(exposures.count, 1)
        XCTAssertEqual(stats.freshCalls, ["main"])
        guard case let .loaded(targets) = store.phase(for: .workspace("acme")) else { return XCTFail("not loaded") }
        XCTAssertEqual(targets.map(\.kind), [.site(host: "app.acme.example.com")])
    }
}
