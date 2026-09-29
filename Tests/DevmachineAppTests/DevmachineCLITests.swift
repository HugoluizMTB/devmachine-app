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

final class AdminMachineCacheTests: XCTestCase {
    func testPicksTheFirstNonSelfMachine() throws {
        let cache = AdminMachineCache()
        let runner = CLIRecordingRunner(result: (#"[{"name":"laptop","self":true},{"name":"box"}]"#, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)
        XCTAssertEqual(try cache.name { cli }, "box")
    }

    func testAnAnswerIsKeptForTheRestOfTheRun() throws {
        let cache = AdminMachineCache()
        let runner = CLIRecordingRunner(result: (#"[{"name":"laptop","self":true},{"name":"box"}]"#, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)
        XCTAssertEqual(try cache.name { cli }, "box")
        XCTAssertEqual(try cache.name { cli }, "box")
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testAFailedLookupIsReportedAndTriedAgain() throws {
        let cache = AdminMachineCache()
        XCTAssertThrowsError(try cache.name { throw DevmachineCLIError.executableNotFound(["/opt/devmachine"]) })
        let runner = CLIRecordingRunner(result: (#"[{"name":"box"}]"#, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)
        XCTAssertEqual(try cache.name { cli }, "box")
    }

    func testNoNonSelfMachineReportsAClearError() {
        let cache = AdminMachineCache()
        let runner = CLIRecordingRunner(result: (#"[{"name":"laptop","self":true}]"#, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)
        XCTAssertThrowsError(try cache.name { cli }) { error in
            XCTAssertEqual(error.localizedDescription, "No machine is configured. Run `devmachine machines add` first.")
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

final class DevmachineCLIAutoDetectEndpointsTests: XCTestCase {
    func testConfigPathDecodesThePathAndItsSource() throws {
        let runner = CLIRecordingRunner(result: (
            #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let result = try cli.configPath()

        XCTAssertEqual(result, CLIConfigPath(path: "/Users/alice/.config/devmachine", source: "default"))
        XCTAssertEqual(runner.calls.last?.args, ["--format", "json", "config", "path"])
    }

    func testConfigShowDecodesMachinesWorkspacesAndDomain() throws {
        let body = #"""
        {
          "machines": [
            {"name": "acme", "hosts": ["100.64.0.5", "203.0.113.10"], "admin_user": "root", "port": 22, "workspaces": ["alice"]},
            {"name": "mac", "hosts": [], "admin_user": "", "port": 0, "workspaces": [], "self": true}
          ],
          "workspaces": [{"name": "alice", "machine": "acme", "user": "alice"}],
          "domain": "example.com"
        }
        """#
        let runner = CLIRecordingRunner(result: (body, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let result = try cli.configShow()

        XCTAssertEqual(result.domain, "example.com")
        XCTAssertEqual(result.machines.count, 2)
        XCTAssertEqual(result.machines[0].hosts, ["100.64.0.5", "203.0.113.10"])
        XCTAssertFalse(result.machines[0].isSelf)
        XCTAssertTrue(result.machines[1].isSelf)
        XCTAssertEqual(runner.calls.last?.args, ["--format", "json", "config", "show"])
    }

    func testAliasesDecodesEveryEntry() throws {
        let body = #"""
        {"aliases": [
          {"name": "alice-devmachine", "host": "100.64.0.5", "user": "alice", "port": 22}
        ]}
        """#
        let runner = CLIRecordingRunner(result: (body, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let result = try cli.aliases()

        XCTAssertEqual(result, [CLIAlias(name: "alice-devmachine", host: "100.64.0.5", user: "alice", port: 22)])
        XCTAssertEqual(runner.calls.last?.args, ["--format", "json", "aliases"])
    }

    func testPackagesDecodesInstalledOnAndReportsMachineMembership() throws {
        let body = #"""
        {"packages": [
          {"name": "devmachine-app", "scope": "machine", "installed_on": ["machine acme"]},
          {"name": "base", "scope": "machine", "installed_on": ["machine acme", "machine mac"]}
        ]}
        """#
        let runner = CLIRecordingRunner(result: (body, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let result = try cli.packages()

        let devmachineApp = try XCTUnwrap(result.first { $0.name == "devmachine-app" })
        XCTAssertTrue(devmachineApp.isInstalled(onMachine: "acme"))
        XCTAssertFalse(devmachineApp.isInstalled(onMachine: "mac"))
        XCTAssertEqual(runner.calls.last?.args, ["--format", "json", "packages", "list"])
    }

    func testRunWithPackageJoinsMachinePackageAndArgs() throws {
        let runner = CLIRecordingRunner(result: ("stats output", "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let output = try cli.run(machine: "acme", package: "devmachine-app", args: ["stats"])

        XCTAssertEqual(output, "stats output")
        XCTAssertEqual(runner.calls.last?.args, [
            "run", "--machine", "acme", "--package", "devmachine-app", "--", "stats",
        ])
    }

    func testUnknownPackageCommandIsRecognizedFromTheCLIsOwnWording() {
        let runner = CLIRecordingRunner(result: ("", #"error: devmachine-app does not accept "stats". It accepts context"#, 1))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        XCTAssertThrowsError(try cli.run(machine: "acme", package: "devmachine-app", args: ["stats"])) { error in
            guard let cliError = error as? DevmachineCLIError else {
                return XCTFail("expected DevmachineCLIError")
            }
            XCTAssertTrue(cliError.isUnknownPackageCommand)
        }
    }

    func testAConnectionFailureIsNotAnUnknownPackageCommand() {
        let runner = CLIRecordingRunner(result: ("", "ssh: connect to host acme port 22: Connection refused", 1))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        XCTAssertThrowsError(try cli.run(machine: "acme", package: "devmachine-app", args: ["stats"])) { error in
            guard let cliError = error as? DevmachineCLIError else {
                return XCTFail("expected DevmachineCLIError")
            }
            XCTAssertFalse(cliError.isUnknownPackageCommand)
        }
    }
}
