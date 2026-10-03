import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
private func eventually(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("condition never became true"); return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// A CLI with one server, `box`, that has caddy. What `packages list` and
/// `dns providers` answer moves as the test adds a package and syncs.
private final class DNSSetupCLIRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    private var storedInputs: [Data?] = []
    var declared: [String] = []
    var providers = #"{"providers":[]}"#
    var secretFails = false
    /// A CLI 0.7.27+ reports kinds and credentials; its hostinger secret is
    /// named apart from the package, to prove the name is read.
    var reportsKinds = false

    var calls: [[String]] { lock.withLock { storedCalls } }
    var inputs: [Data?] { lock.withLock { storedInputs } }

    func set(_ change: (DNSSetupCLIRunner) -> Void) {
        lock.withLock { change(self) }
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.withLock { storedInputs.append(input) }
        return try runCapturing(executable: executable, args: args, environment: environment)
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(args)
        let declared = self.declared
        let providers = self.providers
        let secretFails = self.secretFails
        let reportsKinds = self.reportsKinds
        lock.unlock()
        switch args {
        case ["--format", "json", "machines", "list"]:
            return (#"[{"name":"laptop","self":true},{"name":"box"}]"#, "", 0)
        case ["--format", "json", "workspaces", "list"]:
            return (#"{"workspaces":[{"name":"alice","machine":"box","user":"alice","packages":[]}]}"#, "", 0)
        case ["--format", "json", "config", "show"]:
            return (#"{"machines":[],"workspaces":[],"domain":"example.com"}"#, "", 0)
        case ["--format", "json", "packages", "list"]:
            let on = { (name: String) in declared.contains(name) ? #"["machine box"]"# : "[]" }
            if reportsKinds {
                return (#"""
                {"packages":[
                    {"name":"caddy","scope":"machine","summary":"A reverse proxy.","credentials":[],"installed_on":["machine box"]},
                    {"name":"hostinger","scope":"machine","kind":"dns","summary":"DNS zones on Hostinger.",
                     "credentials":[{"name":"hostinger-api","kind":"secret","scope":"machine","env":"HOSTINGER_API_TOKEN"}],
                     "installed_on":\#(on("hostinger"))}
                ]}
                """#, "", 0)
            }
            return (#"""
            {"packages":[
                {"name":"caddy","scope":"machine","summary":"A reverse proxy.","installed_on":["machine box"]},
                {"name":"cloudflare","scope":"machine","summary":"DNS zones on Cloudflare.","installed_on":\#(on("cloudflare"))},
                {"name":"hostinger","scope":"machine","summary":"DNS zones on Hostinger.","installed_on":\#(on("hostinger"))}
            ]}
            """#, "", 0)
        case ["--machine", "box", "--format", "json", "expose", "list"]:
            return ("[]", "", 0)
        case ["--machine", "box", "--format", "json", "dns", "providers"]:
            return (providers, "", 0)
        case ["packages", "add", "hostinger", "--machine", "box", "--yes"]:
            lock.withLock { self.declared.append("hostinger") }
            return ("added hostinger to machine box\n", "", 0)
        case ["secrets", "set", "hostinger", "--stdin"], ["secrets", "set", "hostinger-api", "--stdin"]:
            return secretFails ? ("", "error: the keychain is locked\n", 1) : ("", "", 0)
        case ["machines", "edit", "box", "--set", "hostinger.zones=[example.com, example.net]", "--yes"]:
            return declared.contains("hostinger")
                ? ("set hostinger.zones\n", "", 0)
                : ("", "error: hostinger is not installed on box\n", 1)
        default:
            return ("", "unexpected args: \(args)", 1)
        }
    }
}

private final class FakeSyncRunner: MachineJobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    var status: Int32 = 0
    var onRun: ([String]) -> Void = { _ in }

    var calls: [[String]] { lock.withLock { storedCalls } }

    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        lock.withLock { storedCalls.append(arguments) }
        output("ran \(arguments.first ?? "")")
        if status != 0 { output("error: 1 task(s) failed on box: exit status 2") }
        onRun(arguments)
        return status
    }
}

@MainActor
final class DNSSetupStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "dev.devmachine.app.dns.setup.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func loadedStore(
        _ cli: DNSSetupCLIRunner, sync: FakeSyncRunner = FakeSyncRunner(), canRunSync: Bool = true,
        canEditSettings: Bool = true, center: MachineJobCenter? = nil
    ) async throws -> CaddyStore {
        let service = CaddyService(cli: DevmachineCLI(executable: "/fake/devmachine", runner: cli))
        let center = center ?? MachineJobCenter(runner: sync, successSeconds: 60)
        let setup = DNSSetupStore(
            service: service, center: { center }, canRunSync: { canRunSync },
            canEditMachineSettings: { canEditSettings })
        let store = CaddyStore(
            service: service, selection: SitesMachineSelection(defaults: defaults), dnsSetup: setup)
        store.refresh()
        try await eventually { store.dnsSetup.state != .unknown }
        return store
    }

    func testAServerWithNoProviderShowsTheProvidersOnOffer() async throws {
        let store = try await loadedStore(DNSSetupCLIRunner())

        XCTAssertEqual(store.dnsSetup.state, .noneInstalled)
        XCTAssertEqual(store.dnsSetup.catalog.map(\.name), ["cloudflare", "hostinger"])
        XCTAssertEqual(store.dnsSetup.machine, "box")
    }

    func testInstallAddsThePackageStoresTheTokenOnStdinAndAsksForSync() async throws {
        let cli = DNSSetupCLIRunner()
        let store = try await loadedStore(cli)

        await store.dnsSetup.install("hostinger", token: "tok-secret-123")

        XCTAssertEqual(store.dnsSetup.state, .notSynced(provider: "hostinger", problem: .notApplied))
        XCTAssertTrue(cli.calls.contains(["packages", "add", "hostinger", "--machine", "box", "--yes"]))
        XCTAssertTrue(cli.calls.contains(["secrets", "set", "hostinger", "--stdin"]))
        XCTAssertFalse(cli.calls.flatMap { $0 }.contains { $0.contains("tok-secret-123") })
        XCTAssertTrue(cli.inputs.contains(Data("tok-secret-123\n".utf8)))
        XCTAssertEqual(store.dnsSetup.savedToken, "hostinger")
        try await eventually { cli.calls.filter { $0 == ["--format", "json", "packages", "list"] }.count >= 2 }
        XCTAssertEqual(store.dnsSetup.declared, ["hostinger"])
    }

    func testATokenTheCLICouldNotStoreFailsWithoutShowingTheValue() async throws {
        let cli = DNSSetupCLIRunner()
        cli.secretFails = true
        let store = try await loadedStore(cli)

        await store.dnsSetup.install("hostinger", token: "tok-9")

        guard case let .failed(step, cause, details) = store.dnsSetup.state else {
            return XCTFail("expected a failure, got \(store.dnsSetup.state)")
        }
        XCTAssertEqual(step, .saveToken)
        XCTAssertFalse(cause.contains("tok-9") || details.contains("tok-9"))
        XCTAssertTrue(details.contains("keychain is locked"))
    }

    func testSyncRunsTheProviderAloneThenThePushAsACornerJobAndIsReadyOnceZonesAnswer() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let sync = FakeSyncRunner()
        sync.onRun = { arguments in
            if arguments.first == "credentials" {
                cli.set { $0.providers = #"{"providers":[{"name":"hostinger","zones":["example.com"]}]}"# }
            }
        }
        let center = MachineJobCenter(runner: sync, successSeconds: 60)
        let store = try await loadedStore(cli, sync: sync, center: center)
        XCTAssertEqual(store.dnsSetup.state, .notSynced(provider: "hostinger", problem: .notApplied))

        let id = try XCTUnwrap(store.dnsSetup.sync("hostinger"))

        XCTAssertEqual(store.dnsSetup.state, .working(.sync))
        XCTAssertEqual(center.job(id)?.plan.title, "Sync hostinger on box")
        XCTAssertEqual(center.job(id)?.plan.machine, "box")
        try await eventually { store.dnsSetup.state == .ready }
        XCTAssertEqual(sync.calls, [
            ["sync", "--machine", "box", "--tags", "hostinger", "--yes"],
            ["credentials", "push", "--machine", "box", "--yes"],
        ])
        XCTAssertEqual(center.job(id)?.log.lines.first, "$ devmachine sync --machine box --tags hostinger --yes")
        XCTAssertEqual(store.dnsProviders, ["hostinger"])
    }

    func testTheTokenNeverReachesTheSyncJob() async throws {
        let cli = DNSSetupCLIRunner()
        let sync = FakeSyncRunner()
        let center = MachineJobCenter(runner: sync, successSeconds: 60)
        let store = try await loadedStore(cli, sync: sync, center: center)
        await store.dnsSetup.install("hostinger", token: "tok-secret-123")

        let id = try XCTUnwrap(store.dnsSetup.sync("hostinger"))

        try await eventually { sync.calls.count == 2 }
        let job = try XCTUnwrap(center.job(id))
        XCTAssertFalse((job.plan.steps.flatMap { $0 } + job.log.lines).contains { $0.contains("tok-secret-123") })
    }

    func testASyncThatLeavesNoZoneKeepsAskingForIt() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let sync = FakeSyncRunner()
        sync.onRun = { _ in cli.set { $0.providers = #"{"providers":[{"name":"hostinger","zones":null}]}"# } }
        let store = try await loadedStore(cli, sync: sync)

        store.dnsSetup.sync("hostinger")

        try await eventually { store.dnsSetup.state == .notSynced(provider: "hostinger", problem: .noZones) }
    }

    func testAFailedSyncShowsTheCLIsReasonAndCanBeDismissed() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let sync = FakeSyncRunner()
        sync.status = 2
        let center = MachineJobCenter(runner: sync, successSeconds: 60)
        let store = try await loadedStore(cli, sync: sync, center: center)

        let id = try XCTUnwrap(store.dnsSetup.sync("hostinger"))

        try await eventually { if case .failed = store.dnsSetup.state { return true } else { return false } }
        XCTAssertEqual(sync.calls.count, 1, "the push never runs after a failed sync")
        guard case let .failed(step, cause, details) = store.dnsSetup.state else {
            return XCTFail("expected a failure, got \(store.dnsSetup.state)")
        }
        XCTAssertEqual(step, .sync)
        XCTAssertEqual(cause, "1 task(s) failed on box: exit status 2")
        XCTAssertEqual(details, center.job(id)?.log.lines.joined(separator: "\n"))
        XCTAssertTrue(details.contains("$ devmachine sync --machine box --tags hostinger --yes"))

        store.dnsSetup.dismissFailure()
        XCTAssertEqual(store.dnsSetup.state, .notSynced(provider: "hostinger", problem: .notApplied))
        XCTAssertNil(center.job(id), "the failed job leaves the corner with the card's failure")
    }

    func testAFailedSyncRetriedInTheCornerEndsTheCardWhenItSucceeds() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let sync = FakeSyncRunner()
        sync.status = 2
        let center = MachineJobCenter(runner: sync, successSeconds: 60)
        let store = try await loadedStore(cli, sync: sync, center: center)
        var ended: [String] = []
        let refresh = store.dnsSetup.onSyncEnded
        store.dnsSetup.onSyncEnded = { machine in
            ended.append(machine)
            refresh(machine)
        }
        let id = try XCTUnwrap(store.dnsSetup.sync("hostinger"))
        try await eventually { if case .failed = store.dnsSetup.state { return true } else { return false } }

        sync.status = 0
        sync.onRun = { arguments in
            if arguments.first == "credentials" {
                cli.set { $0.providers = #"{"providers":[{"name":"hostinger","zones":["example.com"]}]}"# }
            }
        }
        center.retry(id)

        XCTAssertEqual(store.dnsSetup.state, .working(.sync))
        try await eventually { store.dnsSetup.state == .ready }
        XCTAssertEqual(ended, ["box", "box"])
    }

    func testRunSyncAgainOnTheCardRetriesTheFailedJobInPlace() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let sync = FakeSyncRunner()
        sync.status = 2
        let center = MachineJobCenter(runner: sync, successSeconds: 60)
        let store = try await loadedStore(cli, sync: sync, center: center)
        let id = try XCTUnwrap(store.dnsSetup.sync("hostinger"))
        try await eventually { if case .failed = store.dnsSetup.state { return true } else { return false } }

        sync.status = 0
        store.dnsSetup.retrySync()

        try await eventually { sync.calls.count == 3 }
        XCTAssertEqual(center.jobs.map(\.id), [id])
    }

    func testAFailedJobDismissedInTheCornerTakesTheCardsFailureWithIt() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let sync = FakeSyncRunner()
        sync.status = 2
        let center = MachineJobCenter(runner: sync, successSeconds: 60)
        let store = try await loadedStore(cli, sync: sync, center: center)
        let id = try XCTUnwrap(store.dnsSetup.sync("hostinger"))
        try await eventually { if case .failed = store.dnsSetup.state { return true } else { return false } }

        center.dismiss(id)

        XCTAssertEqual(store.dnsSetup.state, .notSynced(provider: "hostinger", problem: .notApplied))
    }

    func testASecondSyncWhileOneRunsStartsNothing() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let center = MachineJobCenter(runner: FakeSyncRunner(), successSeconds: 60)
        let store = try await loadedStore(cli, center: center)

        XCTAssertNotNil(store.dnsSetup.sync("hostinger"))
        XCTAssertNil(store.dnsSetup.sync("hostinger"))

        XCTAssertEqual(center.jobs.count, 1)
    }

    func testAnOldCLINeverSyncsFromTheApp() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let sync = FakeSyncRunner()
        let center = MachineJobCenter(runner: sync, successSeconds: 60)
        let store = try await loadedStore(cli, sync: sync, canRunSync: false, center: center)

        XCTAssertNil(store.dnsSetup.sync("hostinger"))

        XCTAssertEqual(center.jobs, [])
        XCTAssertEqual(sync.calls, [])
    }

    func testAProviderThatAnswersWithZonesShowsNoCard() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["cloudflare"]
        cli.providers = #"{"providers":[{"name":"cloudflare","zones":["example.com"]}]}"#

        let store = try await loadedStore(cli)

        XCTAssertEqual(store.dnsSetup.state, .ready)
        XCTAssertFalse(store.dnsSetup.state.showsCard)
    }

    func testThisMacGetsNoCard() async throws {
        let store = try await loadedStore(DNSSetupCLIRunner())

        store.select("laptop")

        XCTAssertNil(store.dnsSetup.machine)
        XCTAssertEqual(store.dnsSetup.state, .unknown)
    }

    func testANewCLIStoresTheTokenUnderTheCredentialThePackageDeclares() async throws {
        let cli = DNSSetupCLIRunner()
        cli.reportsKinds = true
        let store = try await loadedStore(cli)
        XCTAssertEqual(store.dnsSetup.catalog.map(\.name), ["hostinger"])

        await store.dnsSetup.install("hostinger", token: "tok-1")

        XCTAssertTrue(cli.calls.contains(["secrets", "set", "hostinger-api", "--stdin"]))
        XCTAssertFalse(cli.calls.contains(["secrets", "set", "hostinger", "--stdin"]))
    }

    func testInstallSetsTheZonesAfterTheAddAndBeforeTheToken() async throws {
        let cli = DNSSetupCLIRunner()
        let store = try await loadedStore(cli)

        await store.dnsSetup.install("hostinger", token: "tok-1", zones: "example.com, example.net")

        let edit = ["machines", "edit", "box", "--set", "hostinger.zones=[example.com, example.net]", "--yes"]
        let add = cli.calls.firstIndex(of: ["packages", "add", "hostinger", "--machine", "box", "--yes"])
        let zones = cli.calls.firstIndex(of: edit)
        let secret = cli.calls.firstIndex(of: ["secrets", "set", "hostinger", "--stdin"])
        XCTAssertNotNil(add)
        XCTAssertNotNil(zones)
        XCTAssertLessThan(add ?? 0, zones ?? 0)
        XCTAssertLessThan(zones ?? 0, secret ?? 0)
        XCTAssertEqual(store.dnsSetup.state, .notSynced(provider: "hostinger", problem: .notApplied))
    }

    func testAnOlderCLINeverRunsMachinesEdit() async throws {
        let cli = DNSSetupCLIRunner()
        let store = try await loadedStore(cli, canEditSettings: false)

        await store.dnsSetup.install("hostinger", token: "tok-1", zones: "example.com, example.net")

        XCTAssertFalse(cli.calls.contains { $0.first == "machines" && $0.contains("edit") })
        XCTAssertTrue(cli.calls.contains(["secrets", "set", "hostinger", "--stdin"]))
    }

    func testZonesSavedOnAMachineWithTheProviderStillAskForSync() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        cli.providers = #"{"providers":[{"name":"hostinger","zones":[]}]}"#
        let store = try await loadedStore(cli)

        await store.dnsSetup.saveZones("hostinger", zones: "example.com, example.net")

        XCTAssertTrue(cli.calls.contains(
            ["machines", "edit", "box", "--set", "hostinger.zones=[example.com, example.net]", "--yes"]))
        XCTAssertEqual(store.dnsSetup.savedZones, "hostinger")
        XCTAssertEqual(store.dnsSetup.state, .notSynced(provider: "hostinger", problem: .noZones))
    }

    func testZonesThatAreNotNamesNeverReachTheCLI() async throws {
        let cli = DNSSetupCLIRunner()
        cli.declared = ["hostinger"]
        let store = try await loadedStore(cli)

        await store.dnsSetup.saveZones("hostinger", zones: "example.com]: x")

        XCTAssertFalse(cli.calls.contains { $0.first == "machines" && $0.contains("edit") })
    }
}
