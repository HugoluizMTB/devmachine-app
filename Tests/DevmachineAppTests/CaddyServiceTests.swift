import XCTest
import DevmachineCore
@testable import DevmachineApp

private let statsJSON = #"""
{
    "collected_at": "2026-09-29T00:00:00Z",
    "memory": {"total_bytes": 0, "used_bytes": 0, "available_bytes": 0},
    "swap": {"total_bytes": 0, "used_bytes": 0},
    "disk": {"path": "/", "used_bytes": 0, "available_bytes": 0, "used_percent": 0},
    "load": {"load1": 0, "load5": 0, "load15": 0},
    "docker": {"available": true, "containers": [{"name": "web", "mem_used_bytes": 0, "mem_limit_bytes": 0, "cpu_percent": 0, "owner": "alice"}]},
    "users": [],
    "ports": [{"port": 8810, "owner": "alice"}],
    "errors": []
}
"""#

/// Answers like a CLI configured with three machines — `laptop` (this Mac),
/// `box` (a server with caddy) and `spare` (a server without it) — and
/// records every call, so a test can check each one names its machine.
final class MultiMachineCLIRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    private var failing: Set<String>
    private let packagesAvailable: Bool
    private let exposeWarning: String?

    init(failing: Set<String> = [], packagesAvailable: Bool = true, exposeWarning: String? = nil) {
        self.failing = failing
        self.packagesAvailable = packagesAvailable
        self.exposeWarning = exposeWarning
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(args)
        let failing = self.failing
        lock.unlock()
        let joined = args.joined(separator: " ")
        if let failed = failing.first(where: { joined.contains($0) }) {
            return ("", "\(failed): connection refused", 255)
        }
        switch args {
        case ["--format", "json", "machines", "list"]:
            return (#"[{"name":"laptop","self":true},{"name":"box"},{"name":"spare"}]"#, "", 0)
        case ["--format", "json", "workspaces", "list"]:
            return (#"""
            {"workspaces":[
                {"name":"alice","machine":"box","user":"alice","packages":[]},
                {"name":"bob","machine":"spare","user":"bob","packages":[]}
            ]}
            """#, "", 0)
        case ["--format", "json", "config", "show"]:
            return (#"{"machines":[],"workspaces":[],"domain":"example.com"}"#, "", 0)
        case ["--format", "json", "packages", "list"]:
            guard packagesAvailable else { return ("", "unknown command", 1) }
            return (#"""
            {"packages":[
                {"name":"caddy","scope":"machine","installed_on":["machine box"]},
                {"name":"devmachine-app","scope":"machine","installed_on":["machine box","machine spare"]}
            ]}
            """#, "", 0)
        case ["--machine", "box", "--format", "json", "expose", "list"]:
            return (#"""
            [
                {"host": "app.example.com", "port": 8080, "workspace": "alice", "status": "published"},
                {"host": "old.example.com", "port": 8810, "status": "unmanaged", "note": "adopt it"}
            ]
            """#, "", 0)
        case ["--machine", "spare", "--format", "json", "expose", "list"]:
            return ("null\n", exposeWarning ?? "", 0)
        case ["run", "--machine", "box", "--package", "devmachine-app", "--", "stats"]:
            return (statsJSON, "", 0)
        case ["run", "--machine", "box", "--package", "devmachine-app", "--", "caddy-logs", "--lines", "200"]:
            return ("app.example.com tls handshake ok\nold.example.com refused\n", "", 0)
        case ["--machine", "box", "--format", "json", "dns", "providers"]:
            return (#"{"providers":[{"name":"Cloudflare","zones":["example.com"]}]}"#, "", 0)
        case ["--machine", "box", "--format", "json", "dns", "list", "example.com", "--dns-provider", "Cloudflare"]:
            return (#"{"zone":"example.com","provider":"Cloudflare","records":[{"name":"app","type":"A","value":"203.0.113.10","ttl":300}]}"#, "", 0)
        case ["--machine", "box", "expose", "rm", "old.example.com", "--yes"]:
            return ("", "", 0)
        default:
            return ("", "unexpected args: \(args)", 1)
        }
    }

    /// The calls that act on a server but name no machine — each one fails
    /// with "several machines are configured" in the real CLI.
    var callsWithoutATarget: [[String]] {
        let configLevel: Set<[String]> = [
            ["--format", "json", "machines", "list"],
            ["--format", "json", "workspaces", "list"],
            ["--format", "json", "config", "show"],
            ["--format", "json", "packages", "list"],
        ]
        return calls.filter { !configLevel.contains($0) && !$0.contains("--machine") && !$0.contains("--workspace") }
    }
}

final class CaddyServiceTests: XCTestCase {
    private let box = CLIMachine(name: "box", isSelf: false)
    private let spare = CLIMachine(name: "spare", isSelf: false)
    private let laptop = CLIMachine(name: "laptop", isSelf: true)

    private func service(_ runner: MultiMachineCLIRunner) -> CaddyService {
        CaddyService(cli: DevmachineCLI(executable: "/fake/devmachine", runner: runner))
    }

    func testMachinesAreEveryConfiguredOneInConfigOrder() throws {
        let runner = MultiMachineCLIRunner()

        XCTAssertEqual(try service(runner).machines().map(\.name), ["laptop", "box", "spare"])
    }

    func testTheContextCarriesTheDomainAndWhichMachineEachWorkspaceLivesOn() {
        let runner = MultiMachineCLIRunner()

        let context = service(runner).context()

        XCTAssertEqual(context.domain, "example.com")
        XCTAssertEqual(context.workspaces(on: "box"), ["alice"])
        XCTAssertEqual(context.workspaces(on: "spare"), ["bob"])
        XCTAssertEqual(context.hasCaddy(onMachine: "box"), true)
        XCTAssertEqual(context.hasCaddy(onMachine: "spare"), false)
    }

    func testSitesAreReadFromTheNamedMachineWithItsOwnStats() throws {
        let runner = MultiMachineCLIRunner()
        let service = service(runner)

        let result = try service.sites(on: box, context: service.context())

        guard case .sites(let rows) = result else { return XCTFail("expected sites, got \(result)") }
        XCTAssertEqual(rows.map(\.site.host), ["app.example.com", "old.example.com"])
        XCTAssertEqual(rows[0].workspaceDisplay, "alice")
        XCTAssertEqual(rows[1].workspaceDisplay, "alice")
        XCTAssertTrue(runner.calls.contains(["--machine", "box", "--format", "json", "expose", "list"]))
        XCTAssertTrue(runner.calls.contains(["run", "--machine", "box", "--package", "devmachine-app", "--", "stats"]))
        XCTAssertEqual(runner.callsWithoutATarget, [])
    }

    func testThisMacIsNotSetUpForSitesAndIsNeverAsked() throws {
        let runner = MultiMachineCLIRunner()
        let service = service(runner)
        let context = service.context()
        let before = runner.calls.count

        let result = try service.sites(on: laptop, context: context)

        guard case .notSetUp(let message) = result else { return XCTFail("expected notSetUp, got \(result)") }
        XCTAssertTrue(message.contains("laptop"))
        XCTAssertEqual(runner.calls.count, before)
    }

    func testAServerWithoutCaddyIsNotSetUpForSitesAndIsNeverAsked() throws {
        let runner = MultiMachineCLIRunner()
        let service = service(runner)

        let result = try service.sites(on: spare, context: service.context())

        guard case .notSetUp(let message) = result else { return XCTFail("expected notSetUp, got \(result)") }
        XCTAssertTrue(message.contains("devmachine packages add caddy --machine spare"))
        XCTAssertFalse(runner.calls.contains { $0.contains("expose") })
    }

    func testTheCLIsOwnCaddyWarningAlsoReadsAsNotSetUpWhenPackagesCannotBeRead() throws {
        let runner = MultiMachineCLIRunner(
            packagesAvailable: false,
            exposeWarning: "spare cannot be asked: caddy is not on spare: add it with `devmachine packages add caddy --machine spare`")
        let service = service(runner)

        let result = try service.sites(on: spare, context: service.context())

        guard case .notSetUp = result else { return XCTFail("expected notSetUp, got \(result)") }
    }

    func testAMachineThatCannotBeReachedThrowsItsOwnError() {
        let runner = MultiMachineCLIRunner(failing: ["--machine box --format json expose list"])
        let service = service(runner)

        XCTAssertThrowsError(try service.sites(on: box, context: service.context())) { error in
            XCTAssertTrue(error.localizedDescription.contains("connection refused"))
        }
    }

    func testDNSProvidersAndRecordsAreReadOnTheNamedMachine() throws {
        let runner = MultiMachineCLIRunner()
        let service = service(runner)

        XCTAssertEqual(try service.dnsProviderNames(machine: "box"), ["Cloudflare"])
        XCTAssertEqual(
            try service.dnsRecords(machine: "box", provider: "Cloudflare", zone: "example.com"),
            [DNSRecordRow(name: "app", type: "A", value: "203.0.113.10", ttl: 300)])
        XCTAssertEqual(runner.callsWithoutATarget, [])
    }

    func testRemoveNamesTheSitesMachine() throws {
        let runner = MultiMachineCLIRunner()

        try service(runner).remove(host: "old.example.com", machine: "box")

        XCTAssertEqual(runner.calls.last, ["--machine", "box", "expose", "rm", "old.example.com", "--yes"])
    }

    func testLogsAreReadOnTheNamedMachineAndFilteredToTheHost() throws {
        let runner = MultiMachineCLIRunner()

        XCTAssertEqual(try service(runner).logs(machine: "box", matching: "old.example.com"), "old.example.com refused")
        XCTAssertEqual(runner.callsWithoutATarget, [])
    }
}
