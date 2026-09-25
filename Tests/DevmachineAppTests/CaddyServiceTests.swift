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
        return (#"[{"host":"app.example.com","port":8080,"workspace":"alice"}]"#, "", 0)
    }
}

final class CaddyServiceTests: XCTestCase {
    func testSitesComeFromTheCLIWithTheirWorkspaceOwner() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: CaddyServiceRunner())
        let service = CaddyService(
            cli: cli,
            remote: RemoteService(runner: CaddyServiceRunner())
        )

        XCTAssertEqual(try service.sites(alias: "must-not-be-used"), [
            CaddySite(
                address: "app.example.com",
                target: "127.0.0.1:8080",
                kind: "proxy",
                workspace: "alice"
            )
        ])
    }
}
