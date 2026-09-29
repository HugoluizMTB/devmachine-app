import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class CLIRecordingRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
    }

    private let lock = NSLock()
    private var storedCalls: [Call] = []
    private var storedEnvironments: [[String: String]?] = []
    var result: (stdout: String, stderr: String, exitCode: Int32)

    init(result: (String, String, Int32) = ("", "", 0)) {
        self.result = result
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(Call(executable: executable, args: args))
        storedEnvironments.append(environment)
        let result = self.result
        lock.unlock()
        return result
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }

    var environments: [[String: String]?] {
        lock.lock()
        defer { lock.unlock() }
        return storedEnvironments
    }
}

final class DevmachineCLITests: XCTestCase {
    func testExposeUsesArgumentArrayAndExplicitPublishConsent() throws {
        let runner = CLIRecordingRunner()
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)

        try cli.expose(workspace: "alice;touch /tmp/no", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.calls, [.init(
            executable: "/opt/homebrew/bin/devmachine",
            args: [
                "expose", "add", "alice;touch /tmp/no", "8080",
                "--host", "app.example.com", "--publish",
            ]
        )])
    }

    func testExposeReportsCLIStderr() {
        let runner = CLIRecordingRunner(result: ("", "provider refused the write", 1))

        XCTAssertThrowsError(try DevmachineCLI(executable: "/x", runner: runner)
            .expose(workspace: "alice", port: 8080, host: "app.example.com")) { error in
            XCTAssertEqual(error.localizedDescription, "provider refused the write")
        }
    }

    func testListDecodesTheCLIJSONContract() throws {
        let body = #"[{"host":"app.example.com","port":8080,"workspace":"alice"}]"#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let sites = try DevmachineCLI(executable: "/x", runner: runner).listExposures()

        XCTAssertEqual(sites, [.init(host: "app.example.com", port: 8080, workspace: "alice")])
        XCTAssertEqual(runner.calls.first?.args, ["--format", "json", "expose", "list"])
    }

    func testListWorkspacesDecodesTheCLIJSONContract() throws {
        let body = #"{"workspaces":[{"name":"alice","machine":"main","user":"alice","packages":["workspace"]}]}"#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let workspaces = try DevmachineCLI(executable: "/x", runner: runner).listWorkspaces()

        XCTAssertEqual(workspaces, [
            .init(name: "alice", machine: "main", user: "alice", packages: ["workspace"]),
        ])
        XCTAssertEqual(runner.calls.first?.args, ["--format", "json", "workspaces", "list"])
    }

    func testListWorkspacesReportsCLIStderr() {
        let runner = CLIRecordingRunner(result: ("", "config folder missing", 1))

        XCTAssertThrowsError(try DevmachineCLI(executable: "/x", runner: runner).listWorkspaces()) { error in
            XCTAssertEqual(error.localizedDescription, "config folder missing")
        }
    }

    func testEveryCallKeepsTheInheritedPath() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: nil,
            socketFileExists: { _ in true }, processEnvironment: ["PATH": "/usr/bin"])

        _ = try cli.context(workspace: "acme", session: "main")
        _ = try cli.context(machine: "mac", project: "/Users/alice/acme")
        try cli.expose(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.environments.count, 3)
        for environment in runner.environments {
            XCTAssertEqual(environment?["PATH"], "/usr/bin")
        }
    }

    func testUsesAn1PasswordSocketWhenItExists() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: nil,
            socketFileExists: { $0 == RemoteCommands.onePasswordSocketPath }, processEnvironment: [:])

        try cli.expose(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.environments[0]?["SSH_AUTH_SOCK"], RemoteCommands.onePasswordSocketPath)
    }

    func testFallsBackToTheInheritedSocketWithout1Password() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: nil,
            socketFileExists: { _ in false }, processEnvironment: ["SSH_AUTH_SOCK": "/tmp/inherited.sock"])

        try cli.expose(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.environments[0]?["SSH_AUTH_SOCK"], "/tmp/inherited.sock")
    }

    func testLeavesTheSocketUnsetWithNothingToOffer() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: nil,
            socketFileExists: { _ in false }, processEnvironment: [:])

        try cli.expose(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertNil(runner.environments[0]?["SSH_AUTH_SOCK"])
    }

    func testAnExplicitSettingsOverrideWinsOver1Password() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: "/tmp/custom.sock",
            socketFileExists: { _ in true }, processEnvironment: [:])

        try cli.expose(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.environments[0]?["SSH_AUTH_SOCK"], "/tmp/custom.sock")
    }

    func testResolverReportsEveryCheckedHomebrewLocation() {
        XCTAssertThrowsError(try DevmachineCLI.resolve(exists: { _ in false })) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("/opt/homebrew/bin/devmachine"))
            XCTAssertTrue(message.contains("/usr/local/bin/devmachine"))
            XCTAssertTrue(message.contains("brew install"))
        }
    }
}

final class SelfMachineCacheTests: XCTestCase {
    func testAFailedLookupIsReportedAndTriedAgain() throws {
        let cache = SelfMachineCache()
        XCTAssertThrowsError(try cache.name { throw DevmachineCLIError.executableNotFound(["/opt/devmachine"]) })
        let runner = CLIRecordingRunner(result: (#"[{"name":"alice-mac","self":true}]"#, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)
        XCTAssertEqual(try cache.name { cli }, "alice-mac")
    }

    func testAnAnswerIsKeptForTheRestOfTheRun() throws {
        let cache = SelfMachineCache()
        let runner = CLIRecordingRunner(result: (#"[{"name":"alice-mac","self":true}]"#, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)
        XCTAssertEqual(try cache.name { cli }, "alice-mac")
        XCTAssertEqual(try cache.name { cli }, "alice-mac")
        XCTAssertEqual(runner.calls.count, 1)
    }
}
