import XCTest
import DevmachineCore
@testable import DevmachineApp

/// A CLI with one server, `box`, whose `expose add` and `expose rm` answer
/// whatever the test sets, and which counts every call.
final class PublishScriptRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    private var addOutput: (String, String, Int32)
    private var removeOutput: (String, String, Int32)
    private var sitesJSON: String

    init(
        add: (String, String, Int32) = (PublishScriptRunner.publishedJSON, "", 0),
        remove: (String, String, Int32) = (#"{"host":"app.example.com","workspace":"alice","applied":true,"status":"removed"}"#, "", 0),
        sites: String = #"[{"host":"app.example.com","port":8080,"workspace":"alice","status":"published"}]"#
    ) {
        addOutput = add
        removeOutput = remove
        sitesJSON = sites
    }

    static let publishedJSON = #"{"host":"new.example.com","port":3000,"workspace":"alice","applied":true,"status":"published"}"#

    func setAdd(_ output: (String, String, Int32)) {
        lock.lock()
        addOutput = output
        lock.unlock()
    }

    func setSites(_ json: String) {
        lock.lock()
        sitesJSON = json
        lock.unlock()
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }

    func count(_ fragment: String) -> Int {
        calls.filter { $0.joined(separator: " ").contains(fragment) }.count
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(args)
        let add = addOutput
        let remove = removeOutput
        let sites = sitesJSON
        lock.unlock()
        let joined = args.joined(separator: " ")
        if joined.contains("expose add") { return add }
        if joined.contains("expose rm") { return remove }
        switch args {
        case ["--format", "json", "machines", "list"]:
            return (#"[{"name":"box"}]"#, "", 0)
        case ["--format", "json", "workspaces", "list"]:
            return (#"{"workspaces":[{"name":"alice","machine":"box","user":"alice","packages":[]}]}"#, "", 0)
        case ["--format", "json", "config", "show"]:
            return (#"{"machines":[],"workspaces":[],"domain":"example.com"}"#, "", 0)
        case ["--format", "json", "packages", "list"]:
            return (#"{"packages":[{"name":"caddy","scope":"machine","installed_on":["machine box"]}]}"#, "", 0)
        case ["--machine", "box", "--format", "json", "expose", "list"]:
            return (sites, "", 0)
        case ["--machine", "box", "--format", "json", "dns", "providers"]:
            return (#"{"providers":[]}"#, "", 0)
        default:
            return ("", "unexpected args: \(args)", 1)
        }
    }
}

@MainActor
final class CacheClock {
    var now = Date(timeIntervalSince1970: 2_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
func eventuallyTrue(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("condition never became true"); return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class SitesLocalFirstTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "dev.devmachine.app.sites.localfirst.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(_ runner: PublishScriptRunner, cache: DataCache = DataCache()) -> CaddyStore {
        let store = CaddyStore(
            service: CaddyService(cli: DevmachineCLI(executable: "/fake/devmachine", runner: runner)),
            selection: SitesMachineSelection(defaults: defaults), cache: cache)
        store.liveCardLifetime = 60
        return store
    }

    private func seed(_ cache: DataCache, sites: [ExposedSite]) {
        cache.put(MachineDataKeys.sitesContext, SitesContextSnapshot(
            machines: [CLIMachine(name: "box", isSelf: false)], domain: "example.com",
            workspaces: [CLIWorkspace(name: "alice", machine: "box", user: "alice", packages: [])],
            installedPackages: [CLIPackage(name: "caddy", scope: "machine", installedOn: ["machine box"])]))
        cache.put(MachineDataKeys.sites("box"), ExposureListing(sites: sites, warning: nil))
    }

    private func loaded(_ runner: PublishScriptRunner) async throws -> CaddyStore {
        let store = makeStore(runner)
        store.appear()
        try await eventuallyTrue { !store.isLoading && !store.rows.isEmpty }
        return store
    }

    // MARK: Stale-while-revalidate

    func testCachedSitesDrawAtOnceAndAFreshCacheAsksNothing() {
        let runner = PublishScriptRunner()
        let clock = CacheClock()
        let cache = DataCache(now: { clock.now })
        seed(cache, sites: [ExposedSite(host: "cached.example.com", port: 8080, workspace: "alice", status: .published)])
        let store = makeStore(runner, cache: cache)

        store.appear()

        XCTAssertFalse(store.showsSitesSkeleton)
        XCTAssertEqual(store.rows.map(\.site.host), ["cached.example.com"])
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(runner.count("expose list"), 0)
    }

    func testStaleSitesDrawAtOnceThenTheFreshListReplacesThem() async throws {
        let runner = PublishScriptRunner()
        let clock = CacheClock()
        let cache = DataCache(now: { clock.now })
        seed(cache, sites: [ExposedSite(host: "cached.example.com", port: 8080, workspace: "alice", status: .published)])
        clock.advance(600)
        let store = makeStore(runner, cache: cache)

        store.appear()

        XCTAssertEqual(store.rows.map(\.site.host), ["cached.example.com"])
        XCTAssertFalse(store.showsSitesSkeleton)
        XCTAssertTrue(store.isLoading)
        try await eventuallyTrue { store.rows.map(\.site.host) == ["app.example.com"] }
        XCTAssertEqual(store.selectedState?.refreshedAt, clock.now)
    }

    func testTheRefreshButtonRereadsAFreshCache() async throws {
        let runner = PublishScriptRunner()
        let cache = DataCache()
        seed(cache, sites: [])
        let store = makeStore(runner, cache: cache)

        store.refresh()

        try await eventuallyTrue { runner.count("expose list") == 1 && !store.isLoading }
        XCTAssertEqual(store.rows.map(\.site.host), ["app.example.com"])
    }

    func testAFailedRefreshKeepsTheCachedRowsAndSaysSo() async throws {
        let runner = PublishScriptRunner(sites: "not json")
        let clock = CacheClock()
        let cache = DataCache(now: { clock.now })
        seed(cache, sites: [ExposedSite(host: "cached.example.com", port: 8080, workspace: "alice", status: .published)])
        clock.advance(600)
        let store = makeStore(runner, cache: cache)

        store.appear()
        try await eventuallyTrue { store.selectedState?.refreshError != nil }

        XCTAssertEqual(store.rows.map(\.site.host), ["cached.example.com"])
        XCTAssertNil(store.errorText)
    }

    func testAnUnchangedRefreshKeepsTheSameRows() async throws {
        let runner = PublishScriptRunner()
        let store = try await loaded(runner)
        let before = store.rows

        store.refresh()
        try await eventuallyTrue { runner.count("expose list") == 2 && !store.isLoading }

        XCTAssertEqual(store.rows, before)
        XCTAssertEqual(store.rows.map(\.id), before.map(\.id))
    }

    // MARK: Publishing

    func testAPublishShowsItsStepsThenTheLiveAddress() async throws {
        let runner = PublishScriptRunner()
        let store = try await loaded(runner)

        store.addSubdomain(SubdomainRequest(host: "new.example.com", port: 3000, managedDNS: true), workspace: "alice")

        XCTAssertEqual(store.jobs.count, 1)
        XCTAssertEqual(store.jobs[0].progress.headline, "Publishing new.example.com…")
        XCTAssertEqual(store.jobs[0].progress.steps.map(\.state), [.running, .waiting])
        try await eventuallyTrue { store.jobs.first?.progress.isFinished == true }
        XCTAssertEqual(store.jobs[0].progress.outcome, .live(URL(string: "https://new.example.com")!))
        XCTAssertTrue(runner.calls.contains([
            "--format", "json", "expose", "add", "alice", "3000", "--host", "new.example.com", "--publish",
        ]))
    }

    func testAPublishRereadsThatMachinesSitesAtOnce() async throws {
        let runner = PublishScriptRunner()
        let store = try await loaded(runner)
        runner.setSites(#"[{"host":"app.example.com","port":8080,"workspace":"alice","status":"published"},{"host":"new.example.com","port":3000,"workspace":"alice","status":"published"}]"#)

        store.addSubdomain(SubdomainRequest(host: "new.example.com", port: 3000, managedDNS: true), workspace: "alice")

        try await eventuallyTrue { store.rows.map(\.site.host).contains("new.example.com") }
        XCTAssertEqual(runner.count("expose list"), 2)
        XCTAssertTrue(store.cache.isFresh(MachineDataKeys.sites("box")))
    }

    func testAPendingPublishSaysItWaitsForASyncAndWhy() async throws {
        let runner = PublishScriptRunner(add: (
            #"{"host":"new.example.com","port":3000,"workspace":"alice","applied":false,"status":"pending","note":"box could not be reached"}"#,
            "box could not be reached (timeout); the DNS record is printed to create by hand\n", 0))
        let store = try await loaded(runner)

        store.addSubdomain(SubdomainRequest(host: "new.example.com", port: 3000, managedDNS: true), workspace: "alice")
        try await eventuallyTrue { store.jobs.first?.progress.isFinished == true }

        XCTAssertEqual(store.jobs[0].progress.outcome, .saved(reason: "box could not be reached"))
        XCTAssertEqual(store.jobs[0].progress.headline, "Saved; will apply on next sync")
    }

    func testAFailedPublishKeepsTheCLIsStderrAndRetryRunsItAgain() async throws {
        let stderr = "caddy refused the new /etc/caddy/sites.d/alice.caddy, so the old one stays"
        let runner = PublishScriptRunner(add: ("", stderr, 1))
        let store = try await loaded(runner)

        store.addSubdomain(SubdomainRequest(host: "new.example.com", port: 3000, managedDNS: true), workspace: "alice")
        try await eventuallyTrue { store.jobs.first?.progress.isFinished == true }
        XCTAssertEqual(store.jobs[0].progress.outcome, .failed(details: stderr))

        runner.setAdd((PublishScriptRunner.publishedJSON, "", 0))
        let id = store.jobs[0].id
        store.retry(id)
        XCTAssertEqual(store.jobs[0].progress.outcome, .running)
        try await eventuallyTrue { store.jobs.first?.progress.isFinished == true }

        XCTAssertEqual(store.jobs.map(\.id), [id])
        XCTAssertEqual(store.jobs[0].progress.outcome, .live(URL(string: "https://new.example.com")!))
        XCTAssertEqual(runner.count("expose add"), 2)
    }

    func testAFailureBeforeAnythingWasRecordedReadsNothingAgain() async throws {
        let runner = PublishScriptRunner(add: ("", "caddy is not on box", 1))
        let store = try await loaded(runner)

        store.addSubdomain(SubdomainRequest(host: "new.example.com", port: 3000, managedDNS: true), workspace: "alice")
        try await eventuallyTrue { store.jobs.first?.progress.isFinished == true }

        XCTAssertEqual(runner.count("expose list"), 1)
    }

    func testARemovalShowsItsCardAndRereadsTheSites() async throws {
        let runner = PublishScriptRunner()
        let store = try await loaded(runner)
        runner.setSites("[]")

        store.remove(host: "app.example.com")

        XCTAssertEqual(store.removingHost, "app.example.com")
        XCTAssertEqual(store.jobs.first?.progress.headline, "Removing app.example.com…")
        try await eventuallyTrue { store.jobs.first?.progress.outcome == .removed }
        XCTAssertNil(store.removingHost)
        try await eventuallyTrue { store.rows.isEmpty }
        XCTAssertTrue(runner.calls.contains([
            "--machine", "box", "--format", "json", "expose", "rm", "app.example.com", "--yes",
        ]))
    }

    func testDismissRemovesTheCard() async throws {
        let runner = PublishScriptRunner()
        let store = try await loaded(runner)
        store.addSubdomain(SubdomainRequest(host: "new.example.com", port: 3000, managedDNS: true), workspace: "alice")
        try await eventuallyTrue { store.jobs.first?.progress.isFinished == true }

        store.dismiss(store.jobs[0].id)

        XCTAssertTrue(store.jobs.isEmpty)
    }

    func testALiveCardLeavesOnItsOwn() async throws {
        let runner = PublishScriptRunner()
        let store = try await loaded(runner)
        store.liveCardLifetime = 0.05

        store.addSubdomain(SubdomainRequest(host: "new.example.com", port: 3000, managedDNS: true), workspace: "alice")

        try await eventuallyTrue { store.jobs.isEmpty }
    }
}
