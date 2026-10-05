import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class PackagesStoreTests: XCTestCase {
    private let main = PackageTarget.machine("main", isSelf: false)

    private func snapshot() -> PackagesSnapshot {
        PackagesSnapshot(
            entries: [
                PackageEntry(name: "docker", scope: "machine", source: "release", summary: "", category: "Containers",
                             platforms: [], needs: [], credentialNames: [], installedOn: []),
                PackageEntry(name: "node", scope: "machine", source: "release", summary: "", category: nil,
                             platforms: [], needs: [], credentialNames: [], installedOn: ["machine main"]),
            ],
            targets: [main], lock: PackagesLock(machines: ["main": [.init(name: "node")]]),
            cliVersion: SemanticVersion(major: 0, minor: 7, patch: 30), configDirectory: "/Users/alice/.config/devmachine")
    }

    func testLoadPublishesStatuses() async {
        let snap = snapshot()
        let store = PackagesStore(read: { snap }, edit: { _ in }, jobs: { nil })
        await store.load()
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.snapshot?.statuses(for: main)["node"], .applied)
        XCTAssertEqual(store.snapshot?.statuses(for: main)["docker"], .available)
    }

    func testApplyRunsEditsInOrderThenRequestsSync() async {
        let snap = snapshot()
        let edits = Recorder()
        let center = MachineJobCenter(runner: NoRunner())
        let store = PackagesStore(read: { snap }, edit: { edits.add($0) }, jobs: { center })
        let ok = await store.apply(PackageBatch(edits: [(main, PackageChanges(adds: ["docker"], removes: ["node"]))]))
        XCTAssertTrue(ok)
        XCTAssertEqual(edits.all, [
            ["packages", "add", "docker", "--machine", "main", "--yes"],
            ["packages", "rm", "node", "--machine", "main", "--yes"],
        ])
        XCTAssertEqual(center.jobs.first?.request, SyncRequest(machine: "main", tags: ["docker"], full: true, reasons: ["Packages"]))
        XCTAssertEqual(center.jobs.first?.phase, .pending)
        XCTAssertFalse(store.applying)
    }

    func testApplyStopsAtFirstFailureWithoutSyncRequest() async {
        let snap = snapshot()
        let edits = Recorder()
        let center = MachineJobCenter(runner: NoRunner())
        let store = PackagesStore(read: { snap }, edit: { args in
            edits.add(args)
            if args[2] == "node" { throw DevmachineCLIError.commandFailed("error: node is not in the release") }
        }, jobs: { center })
        let ok = await store.apply(PackageBatch(edits: [(main, PackageChanges(adds: ["docker", "node", "zsh"], removes: []))]))
        XCTAssertFalse(ok)
        XCTAssertEqual(edits.all.count, 2)
        XCTAssertNotNil(store.applyError)
        XCTAssertTrue(center.jobs.isEmpty)
        XCTAssertFalse(store.applying)
    }

    func testSyncPendingAsksFullWhenARemovalWaits() async {
        var snap = snapshot()
        snap.lock = PackagesLock(machines: ["main": [.init(name: "node"), .init(name: "old")]])
        snap.entries.append(PackageEntry(name: "old", scope: "machine", source: "release", summary: "", category: nil,
                                         platforms: [], needs: [], credentialNames: [], installedOn: []))
        let final = snap
        let center = MachineJobCenter(runner: NoRunner())
        let store = PackagesStore(read: { final }, edit: { _ in }, jobs: { center })
        await store.load()
        store.syncPending(on: main)
        XCTAssertEqual(center.jobs.first?.request?.full, true)
    }

    func testApplyInDemoModeRefusesWithoutEditing() async {
        let edits = Recorder()
        let center = MachineJobCenter(runner: NoRunner())
        let store = PackagesStore(read: { [snap = snapshot()] in snap }, edit: { edits.add($0) },
                                  jobs: { center }, isDemo: { true })
        let ok = await store.apply(PackageBatch(edits: [(main, PackageChanges(adds: [], removes: []))]))
        XCTAssertFalse(ok)
        XCTAssertEqual(store.applyError?.details, "Demo mode never changes a configuration.")
        XCTAssertTrue(edits.all.isEmpty)
        XCTAssertTrue(center.jobs.isEmpty)
    }

    func testEveryJobFinishReadsAgain() async throws {
        let reads = Recorder()
        let snap = snapshot()
        let center = MachineJobCenter(runner: FailsOnceRunner(), successSeconds: 0)
        let store = PackagesStore(read: { reads.add([]); return snap }, edit: { _ in }, jobs: { center })
        _ = await store.apply(PackageBatch(edits: [(main, PackageChanges(adds: ["docker"], removes: []))]))
        XCTAssertEqual(reads.all.count, 1)
        let id = try XCTUnwrap(center.jobs.first?.id)
        center.start(id, full: false)
        try await eventually { reads.all.count == 2 }
        guard case .failed = center.job(id)?.phase else { return XCTFail("expected the first run to fail") }
        center.retry(id)
        try await eventually { reads.all.count == 3 }
        XCTAssertEqual(store.phase, .loaded)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition())
    }

    func testReadFailureIsAnErrorState() async {
        let store = PackagesStore(read: { throw DevmachineCLIError.commandFailed("boom") }, edit: { _ in }, jobs: { nil })
        await store.load()
        guard case .failed = store.phase else { return XCTFail("expected failed") }
    }

    func testAConfigurationChangeReadsAgain() async throws {
        let reads = Recorder()
        let snap = snapshot()
        let store = PackagesStore(read: { reads.add([]); return snap }, edit: { _ in }, jobs: { nil })
        await store.load()
        NotificationCenter.default.post(name: ConfigDirectoryWatcher.changed, object: nil)
        let deadline = Date().addingTimeInterval(2)
        while reads.all.count < 2 && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(reads.all.count, 2)
    }

    func testLoadInDemoModeNeverReads() async {
        let reads = Recorder()
        let snap = snapshot()
        let store = PackagesStore(read: { reads.add([]); return snap },
                                  edit: { _ in }, jobs: { nil }, isDemo: { true })
        await store.load()
        XCTAssertTrue(reads.all.isEmpty)
    }
}

final class PackagesReaderTests: XCTestCase {
    func testReadBuildsTargetsAndEntries() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: PackagesCLIRunner())
        let snap = try PackagesReader.read(cli: cli, readLock: { _ in .unreadable })
        XCTAssertNil(snap.lock)
        XCTAssertEqual(snap.targets, [
            .machine("main", isSelf: false), .machine("mac", isSelf: true), .workspace("acme", machine: "main"),
        ])
        XCTAssertEqual(snap.configDirectory, "/Users/alice/.config/devmachine")
        XCTAssertEqual(snap.cliVersion, SemanticVersion(major: 0, minor: 7, patch: 30))
        XCTAssertEqual(snap.entries, [
            PackageEntry(name: "cloudflare", scope: "machine", source: "release", summary: "DNS", category: "Network",
                         platforms: ["linux"], needs: ["caddy"], credentialNames: ["cloudflare-token"],
                         installedOn: ["machine main"]),
            PackageEntry(name: "caddy", scope: "machine", source: "local", summary: "", category: nil,
                         platforms: [], needs: [], credentialNames: [], installedOn: []),
        ])
    }

    func testAMissingLockIsEmpty() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: PackagesCLIRunner())
        let snap = try PackagesReader.read(cli: cli, readLock: { _ in .missing })
        XCTAssertEqual(snap.lock, PackagesLock(machines: [:]))
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String]] = []
    func add(_ args: [String]) { lock.withLock { calls.append(args) } }
    var all: [[String]] { lock.withLock { calls } }
}

private struct NoRunner: MachineJobRunning {
    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32 { 0 }
}

private final class FailsOnceRunner: MachineJobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0
    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        lock.withLock {
            runs += 1
            return runs == 1 ? 1 : 0
        }
    }
}

private struct PackagesCLIRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        switch args {
        case ["--format", "json", "config", "show"]:
            return #"""
            {"machines":[{"name":"main"},{"name":"mac","self":true}],
             "workspaces":[{"name":"acme","machine":"main","user":"alice"}],"domain":"example.com"}
            """#
        case ["--format", "json", "packages", "list"]:
            return #"""
            {"packages":[
              {"name":"cloudflare","scope":"machine","source":"release","summary":"DNS","category":"Network",
               "platforms":["linux"],"needs":["caddy"],"installed_on":["machine main"],
               "credentials":[{"name":"cloudflare-token","kind":"token"}]},
              {"name":"caddy","scope":"machine","source":"local"}
            ]}
            """#
        case ["version"]:
            return "devmachine 0.7.30\n"
        case ["--format", "json", "config", "path"]:
            return #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#
        default:
            throw DevmachineCLIError.commandFailed("unexpected \(args)")
        }
    }
}
