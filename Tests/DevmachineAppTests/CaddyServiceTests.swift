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
        if args == ["--format", "json", "expose", "list"] {
            return (#"[{"host":"app.example.com","port":8080,"workspace":"alice"}]"#, "", 0)
        }
        if args == ["--format", "json", "machines", "list"] {
            return (#"[{"name":"self","self":true},{"name":"box"}]"#, "", 0)
        }
        if args == ["run", "--machine", "box", "--", "journalctl -u caddy -n 200 --no-pager"] {
            return ("acme.example.com tls handshake ok", "", 0)
        }
        throw NSError(domain: "unexpected remote command", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "unexpected args: \(args)"
        ])
    }
}

final class CaddyServiceTests: XCTestCase {
    func testSitesComeFromTheCLIWithTheirWorkspaceOwner() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(cli: cli)

        XCTAssertEqual(try service.sites(), [
            CaddySite(
                address: "app.example.com",
                target: "127.0.0.1:8080",
                kind: "proxy",
                workspace: "alice"
            )
        ])
    }

    func testLogsRunThroughTheCLIAsTheNonSelfMachinesAdmin() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(cli: cli, adminMachine: AdminMachineCache())

        XCTAssertEqual(try service.logs(), "acme.example.com tls handshake ok")
    }
}
