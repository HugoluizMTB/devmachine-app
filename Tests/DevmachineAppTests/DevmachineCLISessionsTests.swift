import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

final class SessionsCLIRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    private let result: (stdout: String, stderr: String, exitCode: Int32)

    init(result: (String, String, Int32)) {
        self.result = result
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        defer { lock.unlock() }
        storedCalls.append(args)
        return result
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

enum SessionsCLIFixture {
    static let json = """
    {"workspaces":[{"name":"acme","machine":"main","sessions":[{"name":"checkout-flow","windows":2,\
    "path":"/home/acme/acme-web","branch":"feature/checkout-flow","created_at":"2026-10-08T12:00:00Z",\
    "age_seconds":10800,"last_activity_at":"2026-10-08T14:59:58Z","harnesses":["claude"],"busy":true,\
    "attention":false}]},
     {"name":"beta","machine":"main","sessions":[],"error":{"kind":"unreachable",\
    "message":"machine \\"main\\": no address answered: 203.0.113.10"}}]}
    """
}

final class DevmachineCLISessionsTests: XCTestCase {
    private func cli(_ runner: SessionsCLIRunner) -> DevmachineCLI {
        DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)
    }

    func testAsksForEveryWorkspaceInOneCall() throws {
        let runner = SessionsCLIRunner(result: (#"{"workspaces":[]}"#, "", 0))

        _ = try cli(runner).sessions(workspaces: ["acme", "beta"])

        XCTAssertEqual(runner.calls, [
            ["--format", "json", "sessions", "--workspace", "acme", "--workspace", "beta"],
        ])
    }

    func testDecodesTheCLIContract() throws {
        let runner = SessionsCLIRunner(result: (SessionsCLIFixture.json, "", 0))

        let list = try cli(runner).sessions(workspaces: ["acme", "beta"])

        XCTAssertEqual(list, CLISessionList(workspaces: [
            CLISessionWorkspace(
                name: "acme",
                sessions: [CLISession(
                    name: "checkout-flow", windows: 2, path: "/home/acme/acme-web",
                    branch: "feature/checkout-flow", ageSeconds: 10800, harnesses: ["claude"],
                    busy: true, attention: false)],
                error: nil),
            CLISessionWorkspace(
                name: "beta", sessions: [],
                error: CLISessionError(
                    kind: "unreachable", message: "machine \"main\": no address answered: 203.0.113.10")),
        ]))
    }

    func testAnOlderCLIAsksForANewerOne() {
        let runner = SessionsCLIRunner(result: ("", "Error: unknown command \"sessions\" for \"devmachine\"", 1))

        XCTAssertThrowsError(try cli(runner).sessions(workspaces: ["acme"])) { error in
            XCTAssertEqual(error as? DevmachineCLIError, .needsNewerCLI("sessions"))
        }
    }

    func testAnyOtherFailureIsACommandFailure() {
        let runner = SessionsCLIRunner(result: ("", "unknown workspace \"gamma\"", 1))

        XCTAssertThrowsError(try cli(runner).sessions(workspaces: ["gamma"])) { error in
            XCTAssertEqual(error as? DevmachineCLIError, .commandFailed("unknown workspace \"gamma\""))
        }
    }
}
