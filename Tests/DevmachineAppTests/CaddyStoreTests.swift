import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedCaddyRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var failing: Set<String> = []
    private var storedDomain: String

    init(domain: String = "example.com", failing: Set<String> = []) {
        self.storedDomain = domain
        self.failing = failing
    }

    func fail(_ command: String) {
        lock.lock()
        failing.insert(command)
        lock.unlock()
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        let failing = self.failing
        let domain = storedDomain
        lock.unlock()
        let joined = args.joined(separator: " ")
        if let failed = failing.first(where: { joined.contains($0) }) {
            return ("", "\(failed): connection refused", 1)
        }
        switch args {
        case ["--machine", "box", "--format", "json", "expose", "list"]:
            return (#"[{"host": "app.example.com", "port": 8080, "workspace": "alice", "status": "published"}]"#, "", 0)
        case ["--format", "json", "workspaces", "list"]:
            return (#"{"workspaces":[{"name":"alice","machine":"box","user":"alice","packages":[]}]}"#, "", 0)
        case ["--format", "json", "config", "show"]:
            return (#"{"machines":[],"workspaces":[],"domain":"\#(domain)"}"#, "", 0)
        case ["--format", "json", "machines", "list"]:
            return (#"[{"name":"self","self":true},{"name":"box"}]"#, "", 0)
        case ["--machine", "box", "--format", "json", "dns", "providers"]:
            return (#"{"providers":[{"name":"Cloudflare","zones":["example.com"]}]}"#, "", 0)
        case ["--machine", "box", "--format", "json", "dns", "list", "example.com", "--dns-provider", "Cloudflare"]:
            return (#"{"zone":"example.com","provider":"Cloudflare","records":[{"name":"app","type":"A","value":"203.0.113.10","ttl":300}]}"#, "", 0)
        default:
            return ("", "unexpected args: \(args)", 1)
        }
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("condition never became true"); return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class CaddyStoreTests: XCTestCase {
    private func makeStore(_ runner: ScriptedCaddyRunner) -> CaddyStore {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: runner)
        let suiteName = "dev.devmachine.app.caddystore.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return CaddyStore(service: CaddyService(cli: cli), selection: SitesMachineSelection(defaults: defaults))
    }

    func testTheSitesSkeletonShowsUntilTheFirstListArrives() async throws {
        let store = makeStore(ScriptedCaddyRunner())
        XCTAssertTrue(store.showsSitesSkeleton)

        store.refresh()
        XCTAssertTrue(store.showsSitesSkeleton)
        try await waitUntil { !store.isLoading }

        XCTAssertFalse(store.showsSitesSkeleton)
        XCTAssertEqual(store.rows.count, 1)
    }

    func testAFailedFirstListShowsTheErrorNotTheSkeleton() async throws {
        let store = makeStore(ScriptedCaddyRunner(failing: ["expose list"]))

        store.refresh()
        try await waitUntil { store.errorText != nil }

        XCTAssertFalse(store.showsSitesSkeleton)
    }

    func testARefreshAfterTheListArrivedNeverBringsTheSkeletonBack() async throws {
        let store = makeStore(ScriptedCaddyRunner())
        store.refresh()
        try await waitUntil { !store.isLoading }

        store.refresh()

        XCTAssertTrue(store.isLoading)
        XCTAssertFalse(store.showsSitesSkeleton)
    }

    func testAProviderTabShowsItsSkeletonUntilItsRecordsArrive() async throws {
        let store = makeStore(ScriptedCaddyRunner())
        XCTAssertEqual(store.dnsPhase(for: "Cloudflare"), .skeleton)

        store.refresh()
        try await waitUntil { !store.isLoading }
        store.loadRecords(provider: "Cloudflare")
        XCTAssertEqual(store.dnsPhase(for: "Cloudflare"), .skeleton)
        try await waitUntil { store.dnsRecordsByProvider["Cloudflare"] != nil }

        XCTAssertEqual(store.dnsPhase(for: "Cloudflare"), .loaded(
            [DNSRecordRow(name: "app", type: "A", value: "203.0.113.10", ttl: 300)]))
    }

    func testAProviderTabShowsItsOwnFailure() async throws {
        let store = makeStore(ScriptedCaddyRunner(failing: ["dns list"]))
        store.refresh()
        try await waitUntil { !store.isLoading }

        store.loadRecords(provider: "Cloudflare")
        try await waitUntil { store.dnsErrorByProvider["Cloudflare"] != nil }

        XCTAssertEqual(store.dnsPhase(for: "Cloudflare"), .failed(store.dnsErrorByProvider["Cloudflare"] ?? ""))
    }

    func testAProviderTabNeverWaitsForADomainTheConfigurationCouldNotRead() async throws {
        let store = makeStore(ScriptedCaddyRunner(failing: ["machines list"]))

        store.refresh()
        try await waitUntil { store.errorText != nil }

        XCTAssertEqual(store.dnsPhase(for: "Cloudflare"), .failed(store.errorText ?? ""))
    }

    func testAProviderTabNeverWaitsWhenNoDomainIsConfigured() async throws {
        let store = makeStore(ScriptedCaddyRunner(domain: ""))

        store.refresh()
        try await waitUntil { !store.isLoading }

        XCTAssertEqual(store.dnsPhase(for: "Cloudflare"), .failed(CaddyStore.noDomainMessage))
    }
}
