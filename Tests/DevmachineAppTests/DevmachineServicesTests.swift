import XCTest
import DevmachineCore
@testable import DevmachineApp

struct FixtureWorkspaceSource: WorkspaceSource {
    var values: [Workspace] = []
    func workspaces(suffix: String) throws -> [Workspace] { values }
}

private struct CLIServiceRunner: CommandRunner {
    var result: (stdout: String, stderr: String, exitCode: Int32)

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        result
    }
}

struct FixtureSessionSource: SessionSource {
    var remote: [TmuxSession] = []
    var local = LocalSessionSnapshot(sessions: [], harnesses: [:])
    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession] { remote }
    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot { local }
}

final class FixtureContextSource: ContextSource, @unchecked Sendable {
    private let lock = NSLock()
    private var targets: [CommandTarget] = []
    let state: ContextState?
    let gate: DispatchSemaphore?

    init(state: ContextState? = nil, blocked: Bool = false) {
        self.state = state
        gate = blocked ? DispatchSemaphore(value: 0) : nil
    }

    func context(for target: CommandTarget) throws -> ContextState? {
        lock.lock()
        targets.append(target)
        lock.unlock()
        gate?.wait()
        return state
    }

    var calls: [CommandTarget] {
        lock.lock()
        defer { lock.unlock() }
        return targets
    }
}

func fixtureServices(
    workspaces: [Workspace] = [], sessions: [TmuxSession] = [],
    local: LocalSessionSnapshot = LocalSessionSnapshot(sessions: [], harnesses: [:]),
    context: any ContextSource = FixtureContextSource()
) -> DevmachineServices {
    DevmachineServices(
        workspaceSource: FixtureWorkspaceSource(values: workspaces),
        sessionSource: FixtureSessionSource(remote: sessions, local: local),
        contextSource: context)
}

final class DevmachineServicesTests: XCTestCase {
    func testCommandContextSourcePreservesLocalAndRemoteEngineCommands() throws {
        let local = ContextCommandRecorder()
        let remote = ContextCommandRecorder()
        let source = CommandContextSource(
            host: HostRunner(remote: RemoteService(runner: remote), local: local),
            localEngineAvailable: { true })
        let localState = try source.context(for: .local(session: "shell", path: "/Users/alice/dev/acme"))
        XCTAssertEqual(localState?.harness, .claude)
        XCTAssertEqual(remote.calls.count, 0)
        let localCall = try XCTUnwrap(local.calls.first)
        XCTAssertEqual(localCall.0, "/bin/sh")
        XCTAssertTrue(localCall.1.last?.hasSuffix("--project '/Users/alice/dev/acme'") == true)
        XCTAssertNotNil(localCall.2?["PATH"])

        let remoteState = try source.context(for: .remote(alias: "acme-devmachine", session: "dash"))
        XCTAssertEqual(remoteState?.harness, .claude)
        let remoteCall = try XCTUnwrap(remote.calls.first)
        XCTAssertEqual(remoteCall.0, "/usr/bin/ssh")
        XCTAssertEqual(remoteCall.1.last, "devmachine-infer --session 'dash'")
    }

    func testMissingLocalEngineReturnsNoContextWithoutRunningACommand() throws {
        let runner = ContextCommandRecorder()
        let source = CommandContextSource(
            host: HostRunner(local: runner), localEngineAvailable: { false })
        XCTAssertNil(try source.context(for: .local(session: "shell", path: "/Users/alice/dev/acme")))
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testCLIWorkspaceSourceMapsEntriesToTheSSHAliasSuffixInOrder() throws {
        let body = #"""
        {"workspaces":[
            {"name":"alice","machine":"main","user":"alice","packages":["workspace"]},
            {"name":"bob","machine":"main","user":"bob","packages":["workspace"]}
        ]}
        """#
        let runner = CLIServiceRunner(result: (body, "", 0))
        let source = CLIWorkspaceSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        let workspaces = try source.workspaces(suffix: "-lab")

        XCTAssertEqual(workspaces, [
            Workspace(name: "alice", alias: "alice-lab"),
            Workspace(name: "bob", alias: "bob-lab"),
        ])
    }

    func testCLIWorkspaceSourceReturnsEmptyOnCLIFailure() throws {
        let runner = CLIServiceRunner(result: ("", "config folder missing", 1))
        let source = CLIWorkspaceSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        XCTAssertEqual(try source.workspaces(suffix: "-lab"), [])
    }

    func testCLIWorkspaceSourceReturnsEmptyOnMalformedJSON() throws {
        let runner = CLIServiceRunner(result: ("not json", "", 0))
        let source = CLIWorkspaceSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        XCTAssertEqual(try source.workspaces(suffix: "-lab"), [])
    }

    func testContextFacadeReturnsNoContextForUnsupportedHarnesses() throws {
        let source = FixtureContextSource(state: ContextState(
            cwd: "/home/acme/dev", isClaude: true, updatedAt: "now", plan: nil, prs: [], links: []))
        let facade = ContextFacade(source: source)
        let target = CommandTarget.remote(alias: "acme-devmachine", session: "dash")
        XCTAssertNil(try facade.context(for: target, harnesses: [.codex]))
        XCTAssertNil(try facade.context(for: target, harnesses: []))
        XCTAssertEqual(source.calls, [])
        XCTAssertNotNil(try facade.context(for: target, harnesses: [.claude, .codex]))
        XCTAssertEqual(source.calls, [target])
    }
}

private final class ContextCommandRecorder: CommandRunner, @unchecked Sendable {
    var calls: [(String, [String], [String: String]?)] = []
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        calls.append((executable, args, environment))
        return """
        {"cwd":"/home/acme/dev","isClaude":true,"updatedAt":"now","prs":[],"links":[]}
        """
    }
}
