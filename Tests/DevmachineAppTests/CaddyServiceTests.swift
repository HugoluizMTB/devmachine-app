import XCTest
import DevmachineCore
@testable import DevmachineApp

private struct CaddyServiceRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        guard executable == "/fake/devmachine" else {
            throw NSError(domain: "unexpected remote command", code: 1)
        }
        switch args {
        case ["--format", "json", "expose", "list"]:
            return (#"""
            [
                {"host": "app.example.com", "port": 8080, "workspace": "alice", "status": "published"},
                {"host": "old.example.com", "port": 8810, "status": "unmanaged", "note": "adopt it"}
            ]
            """#, "", 0)
        case ["--format", "json", "workspaces", "list"]:
            return (#"{"workspaces":[{"name":"alice","machine":"box","user":"alice","packages":[]}]}"#, "", 0)
        case ["--format", "json", "config", "show"]:
            return (#"{"machines":[],"workspaces":[],"domain":"example.com"}"#, "", 0)
        case ["--format", "json", "machines", "list"]:
            return (#"[{"name":"self","self":true},{"name":"box"}]"#, "", 0)
        case ["run", "--machine", "box", "--package", "devmachine-app", "--", "stats"]:
            return (#"""
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
            """#, "", 0)
        case ["run", "--machine", "box", "--package", "devmachine-app", "--", "caddy-logs", "--lines", "200"]:
            return ("app.example.com tls handshake ok\nold.example.com refused\n", "", 0)
        case ["--machine", "box", "--format", "json", "dns", "providers"]:
            return (#"{"providers":[{"name":"Cloudflare","zones":["example.com"]}]}"#, "", 0)
        case ["--machine", "box", "--format", "json", "dns", "list", "example.com", "--dns-provider", "Cloudflare"]:
            return (#"{"zone":"example.com","provider":"Cloudflare","records":[{"name":"app","type":"A","value":"203.0.113.10","ttl":300}]}"#, "", 0)
        case ["expose", "rm", "old.example.com", "--yes"]:
            return ("", "", 0)
        default:
            throw NSError(domain: "unexpected remote command", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "unexpected args: \(args)"
            ])
        }
    }
}

final class CaddyServiceTests: XCTestCase {
    func testSnapshotResolvesEveryRowsWorkspaceAndDomain() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(cli: cli, adminMachine: AdminMachineCache())

        let snapshot = try service.snapshot()

        XCTAssertEqual(snapshot.domain, "example.com")
        XCTAssertEqual(snapshot.rows.count, 2)
        XCTAssertEqual(snapshot.rows[0].site.host, "app.example.com")
        XCTAssertEqual(snapshot.rows[0].workspaceDisplay, "alice")
        // The unmanaged row carries no workspace, so it falls back to the
        // port's owner and, failing that, the owning container's name.
        XCTAssertEqual(snapshot.rows[1].site.host, "old.example.com")
        XCTAssertEqual(snapshot.rows[1].workspaceDisplay, "alice")
    }

    func testDNSProviderNamesComeFromTheCLI() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(cli: cli, adminMachine: AdminMachineCache())

        XCTAssertEqual(try service.dnsProviderNames(), ["Cloudflare"])
    }

    func testDNSRecordsAreReadForTheGivenZone() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(cli: cli, adminMachine: AdminMachineCache())

        let records = try service.dnsRecords(provider: "Cloudflare", zone: "example.com")

        XCTAssertEqual(records, [DNSRecordRow(name: "app", type: "A", value: "203.0.113.10", ttl: 300)])
    }

    func testRemoveCallsExposeRmWithYes() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(cli: cli, adminMachine: AdminMachineCache())

        XCTAssertNoThrow(try service.remove(host: "old.example.com"))
    }

    func testLogsFilterToTheGivenHost() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(cli: cli, adminMachine: AdminMachineCache())

        XCTAssertEqual(try service.logs(matching: "old.example.com"), "old.example.com refused")
    }
}
