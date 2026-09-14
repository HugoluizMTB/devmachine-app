import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class FakeRunner: CommandRunner, @unchecked Sendable {
    var executable: String?
    var args: [String]?
    var environment: [String: String]?
    let output: String

    init(output: String = "") {
        self.output = output
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        self.executable = executable
        self.args = args
        self.environment = environment
        return output
    }
}

final class RemoteServiceTests: XCTestCase {
    func testSshBaseArgsPutAliasFirstThenDefaultOptions() {
        let args = RemoteService.sshBaseArgs(alias: "acme-devmachine")

        XCTAssertEqual(args.first, "acme-devmachine")
        XCTAssertTrue(args.contains("ConnectTimeout=5"))
        XCTAssertTrue(args.contains("BatchMode=yes"))
        XCTAssertTrue(args.contains("ServerAliveInterval=5"))
        XCTAssertTrue(args.contains("ServerAliveCountMax=2"))
    }

    func testRunCallsSshWithTheRightArgsAndEnvironment() throws {
        let fake = FakeRunner(output: "ok")
        let service = RemoteService(runner: fake)

        let result = try service.run(alias: "acme-devmachine", args: ["devmachine-infer", "--session", "dash"])

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(fake.executable, "/usr/bin/ssh")
        XCTAssertEqual(fake.args, [
            "acme-devmachine",
            "-o", "ConnectTimeout=5",
            "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2",
            "devmachine-infer", "--session", "dash"
        ])
        XCTAssertEqual(fake.environment?["SSH_AUTH_SOCK"], RemoteCommands.onePasswordSocketPath)
    }
}
