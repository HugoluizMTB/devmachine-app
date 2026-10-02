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

    func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedInputs.append(input)
        lock.unlock()
        return try runCapturing(executable: executable, args: args, environment: environment)
    }

    private var storedInputs: [Data?] = []

    var inputs: [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return storedInputs
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
    func testVersionRunsTheVersionCommandAndReturnsItsOutput() throws {
        let runner = CLIRecordingRunner(result: ("0.7.1\n", "", 0))
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)

        XCTAssertEqual(try cli.version(), "0.7.1\n")
        XCTAssertEqual(runner.calls, [.init(executable: "/opt/homebrew/bin/devmachine", args: ["version"])])
    }

    func testVersionFailingThrows() {
        let runner = CLIRecordingRunner(result: ("", "boom", 1))
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)
        XCTAssertThrowsError(try cli.version())
    }

    func testExposeAsksForJSONWithAnArgumentArrayAndExplicitPublishConsent() throws {
        let runner = CLIRecordingRunner()
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)

        _ = try cli.exposeAdd(workspace: "alice;touch /tmp/no", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.calls, [.init(
            executable: "/opt/homebrew/bin/devmachine",
            args: [
                "--format", "json", "expose", "add", "alice;touch /tmp/no", "8080",
                "--host", "app.example.com", "--publish",
            ]
        )])
    }

    func testExposeThroughAnotherMachineNamesIt() throws {
        let runner = CLIRecordingRunner()
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)

        _ = try cli.exposeAdd(workspace: "bob", port: 8080, host: "app.example.com", via: "edge")

        XCTAssertEqual(runner.calls.first?.args, [
            "--format", "json", "expose", "add", "bob", "8080",
            "--host", "app.example.com", "--via", "edge", "--publish",
        ])
    }

    func testExposeHandsBackTheWholeOutputEvenWhenItFailed() throws {
        let runner = CLIRecordingRunner(result: (#"{"status":"pending"}"#, "caddy refused the new file", 1))

        let output = try DevmachineCLI(executable: "/x", runner: runner)
            .exposeAdd(workspace: "alice", port: 8080, host: "app.example.com")

        XCTAssertEqual(output, CLIOutput(stdout: #"{"status":"pending"}"#, stderr: "caddy refused the new file", exitCode: 1))
    }

    func testListDecodesTheCLIJSONContractForTheNamedMachine() throws {
        let body = #"[{"host":"app.example.com","port":8080,"workspace":"alice","status":"published"}]"#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let listing = try DevmachineCLI(executable: "/x", runner: runner).listExposures(machine: "box")

        XCTAssertEqual(listing.sites, [.init(host: "app.example.com", port: 8080, workspace: "alice", status: .published)])
        XCTAssertNil(listing.warning)
        XCTAssertEqual(runner.calls.first?.args, ["--machine", "box", "--format", "json", "expose", "list"])
    }

    func testListReadsNullAsNoSitesAndKeepsTheCLIsWarning() throws {
        let runner = CLIRecordingRunner(result: ("null\n", "box cannot be asked: caddy is not on box\n", 0))

        let listing = try DevmachineCLI(executable: "/x", runner: runner).listExposures(machine: "box")

        XCTAssertEqual(listing.sites, [])
        XCTAssertEqual(listing.warning, "box cannot be asked: caddy is not on box")
        XCTAssertTrue(listing.caddyIsMissing)
    }

    func testRemoveNamesTheMachineAsksForJSONAndSkipsTheCLIsOwnPrompt() throws {
        let runner = CLIRecordingRunner()

        _ = try DevmachineCLI(executable: "/x", runner: runner).exposeRemove(host: "old.example.com", machine: "box")

        XCTAssertEqual(
            runner.calls.first?.args,
            ["--machine", "box", "--format", "json", "expose", "rm", "old.example.com", "--yes"])
    }

    func testDNSProvidersDecodesTheCLIJSONContract() throws {
        let body = #"{"providers":[{"name":"Cloudflare","zones":["example.com"]},{"name":"Hostinger","zones":[],"error":"no token"}]}"#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let providers = try DevmachineCLI(executable: "/x", runner: runner).dnsProviders(machine: "box")

        XCTAssertEqual(providers, [
            DNSProviderAnswer(name: "Cloudflare", zones: ["example.com"], error: nil),
            DNSProviderAnswer(name: "Hostinger", zones: [], error: "no token"),
        ])
        XCTAssertEqual(runner.calls.first?.args, ["--machine", "box", "--format", "json", "dns", "providers"])
    }

    func testAProviderThatFailedWithNullZonesDoesNotFailTheWholeAnswer() throws {
        let body = #"{"providers":[{"name":"hostinger","zones":null,"error":"HOSTINGER_API_TOKEN is not set"}]}"#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let providers = try DevmachineCLI(executable: "/x", runner: runner).dnsProviders(machine: "box")

        XCTAssertEqual(providers, [DNSProviderAnswer(name: "hostinger", zones: [], error: "HOSTINGER_API_TOKEN is not set")])
    }

    func testAddingAPackageNamesTheMachineAndSkipsThePrompt() throws {
        let runner = CLIRecordingRunner(result: ("added hostinger to machine box\n", "", 0))

        try DevmachineCLI(executable: "/x", runner: runner).addPackage("hostinger", machine: "box")

        XCTAssertEqual(runner.calls.first?.args, ["packages", "add", "hostinger", "--machine", "box", "--yes"])
    }

    func testASecretTravelsOnStandardInputAndNeverInTheArguments() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))

        try DevmachineCLI(executable: "/x", runner: runner).setSecret("hostinger", value: "tok-secret-123")

        XCTAssertEqual(runner.calls.first?.args, ["secrets", "set", "hostinger", "--stdin"])
        XCTAssertFalse(runner.calls.flatMap(\.args).contains { $0.contains("tok-secret-123") })
        XCTAssertEqual(runner.inputs.first ?? nil, Data("tok-secret-123\n".utf8))
    }

    func testAnEmptySecretIsRefusedBeforeTheCLIRuns() {
        let runner = CLIRecordingRunner(result: ("", "", 0))

        XCTAssertThrowsError(try DevmachineCLI(executable: "/x", runner: runner).setSecret("hostinger", value: "  "))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testAFailedSecretSaysWhatTheCLISaidWithoutTheValue() {
        let runner = CLIRecordingRunner(result: ("", "error: the keychain is locked\n", 1))

        XCTAssertThrowsError(try DevmachineCLI(executable: "/x", runner: runner).setSecret("hostinger", value: "tok-9")) {
            let message = ($0 as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("keychain is locked"))
            XCTAssertFalse(message.contains("tok-9"))
        }
    }

    func testANewCLIFindsTheDNSProvidersByKindAndReportsTheirCredentials() throws {
        let body = #"""
        {"packages":[
            {"name":"hostinger","scope":"machine","source":"release","summary":"DNS zones on Hostinger.","category":"DNS","kind":"dns",
             "credentials":[{"name":"hostinger","kind":"secret","scope":"machine","env":"HOSTINGER_API_TOKEN"}],"installed_on":["machine box"]},
            {"name":"lookalike","scope":"machine","source":"local","summary":"DNS zones on paper.","credentials":[],"installed_on":[]},
            {"name":"ghost","source":"missing","credentials":null,"installed_on":["machine box"]}
        ]}
        """#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let packages = try DevmachineCLI(executable: "/x", runner: runner).packages()

        XCTAssertEqual(CLIPackage.dnsProviders(in: packages).map(\.name), ["hostinger"])
        XCTAssertEqual(packages.first?.credentials, [
            PackageCredential(name: "hostinger", kind: "secret", scope: "machine", env: "HOSTINGER_API_TOKEN"),
        ])
        XCTAssertEqual(packages.first?.secretName, "hostinger")
    }

    func testAnOlderCLIFindsTheDNSProvidersByTheirSummary() throws {
        let body = #"""
        {"packages":[
            {"name":"hostinger","scope":"machine","source":"release","summary":"DNS zones on Hostinger.","installed_on":["machine box"]},
            {"name":"caddy","scope":"machine","source":"release","summary":"A reverse proxy.","installed_on":[]},
            {"name":"cloudflare","scope":"machine","source":"release","summary":"DNS zones on Cloudflare.","installed_on":null}
        ]}
        """#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let packages = try DevmachineCLI(executable: "/x", runner: runner).packages()

        XCTAssertEqual(CLIPackage.dnsProviders(in: packages).map(\.name), ["hostinger", "cloudflare"])
        XCTAssertNil(packages.first?.credentials)
        XCTAssertEqual(packages.first?.secretName, "hostinger")
    }

    func testAMachineSettingIsSetThroughMachinesEdit() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))

        try DevmachineCLI(executable: "/x", runner: runner)
            .setZones(setting: "hostinger.zones", machine: "box", zones: ["example.com"])

        XCTAssertEqual(
            runner.calls.first?.args, ["machines", "edit", "box", "--set", "hostinger.zones=[example.com]", "--yes"])
    }

    func testDNSListDecodesTheCLIJSONContractAndPassesTheProvider() throws {
        let body = #"{"zone":"example.com","provider":"Cloudflare","records":[{"name":"app","type":"A","value":"203.0.113.10","ttl":300}]}"#
        let runner = CLIRecordingRunner(result: (body, "", 0))

        let records = try DevmachineCLI(executable: "/x", runner: runner)
            .dnsList(machine: "box", provider: "Cloudflare", zone: "example.com")

        XCTAssertEqual(records, [DNSRecordRow(name: "app", type: "A", value: "203.0.113.10", ttl: 300)])
        XCTAssertEqual(runner.calls.first?.args, [
            "--machine", "box", "--format", "json", "dns", "list", "example.com", "--dns-provider", "Cloudflare",
        ])
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
        _ = try cli.exposeAdd(workspace: "acme", port: 8080, host: "app.example.com")

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

        _ = try cli.exposeAdd(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.environments[0]?["SSH_AUTH_SOCK"], RemoteCommands.onePasswordSocketPath)
    }

    func testFallsBackToTheInheritedSocketWithout1Password() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: nil,
            socketFileExists: { _ in false }, processEnvironment: ["SSH_AUTH_SOCK": "/tmp/inherited.sock"])

        _ = try cli.exposeAdd(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertEqual(runner.environments[0]?["SSH_AUTH_SOCK"], "/tmp/inherited.sock")
    }

    func testLeavesTheSocketUnsetWithNothingToOffer() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: nil,
            socketFileExists: { _ in false }, processEnvironment: [:])

        _ = try cli.exposeAdd(workspace: "acme", port: 8080, host: "app.example.com")

        XCTAssertNil(runner.environments[0]?["SSH_AUTH_SOCK"])
    }

    func testAnExplicitSettingsOverrideWinsOver1Password() throws {
        let runner = CLIRecordingRunner(result: ("", "", 0))
        let cli = DevmachineCLI(
            executable: "/x", runner: runner, customSocket: "/tmp/custom.sock",
            socketFileExists: { _ in true }, processEnvironment: [:])

        _ = try cli.exposeAdd(workspace: "acme", port: 8080, host: "app.example.com")

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

    func testListConfigMachinesDecodesTheSameShapeAsConfigShow() throws {
        let body = #"""
        [
          {"name": "acme", "hosts": ["100.64.0.5", "203.0.113.10"], "admin_user": "root", "port": 22, "workspaces": ["alice"]},
          {"name": "beta", "hosts": ["203.0.113.20"], "admin_user": "root", "port": 22, "workspaces": []},
          {"name": "mac", "hosts": [], "admin_user": "", "port": 0, "workspaces": [], "self": true}
        ]
        """#
        let runner = CLIRecordingRunner(result: (body, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let machines = try cli.listConfigMachines()

        XCTAssertEqual(machines.map(\.name), ["acme", "beta", "mac"])
        XCTAssertEqual(machines[0].hosts, ["100.64.0.5", "203.0.113.10"])
        XCTAssertEqual(runner.calls.last?.args, ["--format", "json", "machines", "list"])
    }

    func testNonSelfMachinesDropsTheSelfEntry() throws {
        let body = #"""
        [
          {"name": "acme", "hosts": ["203.0.113.10"], "admin_user": "root", "port": 22, "workspaces": []},
          {"name": "beta", "hosts": ["203.0.113.20"], "admin_user": "root", "port": 22, "workspaces": []},
          {"name": "mac", "hosts": [], "admin_user": "", "port": 0, "workspaces": [], "self": true}
        ]
        """#
        let runner = CLIRecordingRunner(result: (body, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        XCTAssertEqual(try cli.nonSelfMachines().map(\.name), ["acme", "beta"])
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

    func testDoctorBuildsTheCommandLineForANamedMachine() throws {
        let body = #"{"checks":[{"name":"configuration","status":"pass","detail":"ok"}],"ok":true}"#
        let runner = CLIRecordingRunner(result: (body, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let outcome = try cli.doctor(machine: "box")

        XCTAssertEqual(runner.calls.last?.args, ["--format", "json", "doctor", "--machine", "box"])
        XCTAssertEqual(outcome, .report(DoctorReport(
            checks: [DoctorCheck(name: "configuration", status: .pass, detail: "ok")], ok: true)))
    }

    func testMachineDoctorBuildsTheCommandLineForThisMac() throws {
        let body = #"{"checks":[{"name":"ssh","status":"pass","detail":""}],"ok":true}"#
        let runner = CLIRecordingRunner(result: (body, "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let outcome = try cli.machineDoctor()

        XCTAssertEqual(runner.calls.last?.args, ["--format", "json", "machine", "doctor"])
        XCTAssertEqual(outcome, .report(DoctorReport(
            checks: [DoctorCheck(name: "ssh", status: .pass, detail: "")], ok: true)))
    }

    func testDoctorReadsTheReportEvenWhenExitCodeIsOneBecauseAFailingCheckIsNotACommandFailure() throws {
        let body = #"""
        {"checks":[{"name":"connection","status":"fail","detail":"run `devmachine machines trust box`"}],"ok":false}
        """#
        let runner = CLIRecordingRunner(result: (body, "some checks failed", 1))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let outcome = try cli.doctor(machine: "box")

        XCTAssertEqual(outcome, .report(DoctorReport(
            checks: [DoctorCheck(name: "connection", status: .fail, detail: "run `devmachine machines trust box`")],
            ok: false)))
    }

    func testDoctorFallsBackToRawOutputWhenItCannotBeParsed() throws {
        let runner = CLIRecordingRunner(result: ("something this app's parser does not recognize", "", 0))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let outcome = try cli.doctor(machine: "box")

        XCTAssertEqual(outcome, .raw("something this app's parser does not recognize"))
    }

    func testDoctorThrowsTheCLIsStderrWhenNothingCouldBeReportedAtAll() {
        let runner = CLIRecordingRunner(result: ("", "dial tcp: no route to host", 1))
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        XCTAssertThrowsError(try cli.doctor(machine: "box")) { error in
            XCTAssertEqual(error.localizedDescription, "dial tcp: no route to host")
        }
    }
}

final class DevmachineCLITransferTests: XCTestCase {
    private let executable = "/opt/homebrew/bin/devmachine"

    func testDownloadRunsTheCLIWithEveryPathAfterTheFlagsAndReadsItsJSON() throws {
        let json = #"[{"remote":"/home/acme/a b.png","local":"/Users/alice/Downloads/a b.png","bytes":3,"folder":false}]"#
        let runner = CLIRecordingRunner(result: (json, "", 0))
        let cli = DevmachineCLI(executable: executable, runner: runner)

        let files = try cli.download(paths: ["/home/acme/a b.png"], workspace: "acme", to: "/Users/alice/Downloads")

        XCTAssertEqual(files.first?.local, "/Users/alice/Downloads/a b.png")
        XCTAssertEqual(runner.calls.first?.args, [
            "--format", "json", "download", "--workspace", "acme", "--to", "/Users/alice/Downloads", "--",
            "/home/acme/a b.png"
        ])
    }

    func testDownloadKeepsThePerPathErrorsWhenTheCLIExitsNonZero() throws {
        let json = #"[{"remote":"/home/acme/gone","bytes":0,"folder":false,"error":"/home/acme/gone does not exist"}]"#
        let runner = CLIRecordingRunner(result: (json, "Error: /home/acme/gone does not exist\n", 1))
        let cli = DevmachineCLI(executable: executable, runner: runner)

        let files = try cli.download(paths: ["/home/acme/gone"], workspace: "acme", to: "/tmp")

        XCTAssertEqual(files.first?.error, "/home/acme/gone does not exist")
    }

    func testDownloadOnAnOlderCLIAsksForAnUpdate() {
        let runner = CLIRecordingRunner(result: ("", "Error: unknown command \"download\" for \"devmachine\"\n", 1))
        let cli = DevmachineCLI(executable: executable, runner: runner)

        XCTAssertThrowsError(try cli.download(paths: ["/a"], workspace: "acme", to: "/tmp")) { error in
            XCTAssertEqual(error as? DevmachineCLIError, .needsNewerCLI("download"))
            XCTAssertTrue(error.localizedDescription.contains("devmachine update"))
        }
    }

    func testDownloadSurfacesAFailureBeforeAnyPathWasTried() {
        let runner = CLIRecordingRunner(result: ("", "Error: no workspace named acme\n", 1))
        let cli = DevmachineCLI(executable: executable, runner: runner)

        XCTAssertThrowsError(try cli.download(paths: ["/a"], workspace: "acme", to: "/tmp")) { error in
            XCTAssertEqual(error as? DevmachineCLIError, .commandFailed("Error: no workspace named acme\n"))
        }
    }

    func testUploadPointsDirAtTheFolderAndReadsTheRemotePaths() throws {
        let json = #"[{"local":"/Users/alice/x.png","remote":"/home/acme/proj/x-20260930-143012.png","bytes":3}]"#
        let runner = CLIRecordingRunner(result: (json, "", 0))
        let cli = DevmachineCLI(executable: executable, runner: runner)

        let files = try cli.upload(files: ["/Users/alice/x.png"], workspace: "acme", directory: "/home/acme/proj")

        XCTAssertEqual(files.first?.remote, "/home/acme/proj/x-20260930-143012.png")
        XCTAssertEqual(runner.calls.first?.args, [
            "--format", "json", "upload", "--workspace", "acme", "--dir", "/home/acme/proj", "--", "/Users/alice/x.png"
        ])
    }
}
