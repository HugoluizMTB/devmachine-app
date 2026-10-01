import XCTest
import DevmachineCore
@testable import DevmachineApp

struct FixtureWorkspaceSource: WorkspaceSource {
    var values: [Workspace] = []
    func workspaces(resolveAlias: (String) -> String) throws -> [Workspace] { values }
}

private final class CLIServiceRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [(String, [String])] = []
    var result: (stdout: String, stderr: String, exitCode: Int32)

    init(result: (String, String, Int32)) {
        self.result = result
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append((executable, args))
        lock.unlock()
        return result
    }

    var calls: [(String, [String])] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

/// Answers `machines list` with a fixed body and every other call (the
/// engine run itself) with whatever `nextContextResult` holds at the time.
private final class CLIStagedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [(String, [String])] = []
    private let machinesResult: (stdout: String, stderr: String, exitCode: Int32)
    var nextContextResult: (stdout: String, stderr: String, exitCode: Int32) = ("", "", 0)

    init(machines machinesResult: (stdout: String, stderr: String, exitCode: Int32)) {
        self.machinesResult = machinesResult
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append((executable, args))
        lock.unlock()
        return args.contains("machines") ? machinesResult : nextContextResult
    }

    var calls: [(String, [String])] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
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
    private var error: Error?
    private var storedState: ContextState?
    let gate: DispatchSemaphore?

    init(state: ContextState? = nil, failure: Error? = nil, blocked: Bool = false) {
        storedState = state
        error = failure
        gate = blocked ? DispatchSemaphore(value: 0) : nil
    }

    var state: ContextState? {
        get { lock.lock(); defer { lock.unlock() }; return storedState }
        set { lock.lock(); storedState = newValue; lock.unlock() }
    }

    var failure: Error? {
        get { lock.lock(); defer { lock.unlock() }; return error }
        set { lock.lock(); error = newValue; lock.unlock() }
    }

    func context(for target: CommandTarget, settings: AppSettings) throws -> ContextState? {
        lock.lock()
        targets.append(target)
        let error = self.error
        lock.unlock()
        gate?.wait()
        if let error { throw error }
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
    private let settings = AppSettings(
        opsRepoPath: "/Users/alice/dev", hostAlias: "lab", publicIP: "", baseDomain: "")

    func testCLIContextSourceRunsAWorkspaceSessionThroughTheCLI() throws {
        let body = #"{"cwd":"/home/acme/dev","harness":"claude","updatedAt":"now","prs":[],"links":[]}"#
        let runner = CLIServiceRunner(result: (body, "", 0))
        let source = CLIContextSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        let state = try source.context(
            for: .remote(alias: "acme-lab", session: "dash"), settings: settings)

        XCTAssertEqual(state?.harness, .claude)
        XCTAssertEqual(runner.calls.last?.1, [
            "run", "--workspace", "acme", "--package", "devmachine-app",
            "--", "context", "--session", "dash",
        ])
    }

    /// The local machine no longer shells out to the package: it reads the
    /// transcript in-process through `NativeContextEngine`, still gated on
    /// this Mac being a registered `self:true` machine (one `machines list`,
    /// cached — never a `run --machine ... context` call).
    func testCLIContextSourceRunsALocalProjectOnTheNativeEngine() throws {
        let machinesBody = #"[{"name":"other","self":false},{"name":"studio","self":true}]"#
        let runner = CLIStagedRunner(machines: (machinesBody, "", 0))
        let cli: @Sendable () throws -> DevmachineCLI = { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }

        let project = URL(fileURLWithPath: "/Users/alice/dev/acme")
        let projectsDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transcriptDir = projectsDir.appendingPathComponent(ClaudeHarness.slug(for: project))
        try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
        try #"{"timestamp":"2026-01-01T00:00:00Z","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}"#
            .write(to: transcriptDir.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)
        let engine = NativeContextEngine(
            runner: CLIServiceRunner(result: ("", "", 0)),
            resolver: ContextGitHubResolver(runner: CLIServiceRunner(result: ("", "", 0))),
            githubHosts: ["github.com"],
            roots: ContextRoots(claudeProjectsDir: projectsDir)
        )
        let source = CLIContextSource(cli: cli, nativeEngine: engine)

        let state = try source.context(for: .local(session: "shell", path: project.path), settings: settings)

        XCTAssertEqual(state?.harness, .claude)
        XCTAssertTrue(runner.calls.allSatisfy { $0.1.contains("machines") })

        _ = try source.context(for: .local(session: "shell", path: project.path), settings: settings)
        XCTAssertEqual(runner.calls.filter { $0.1.first == "--format" }.count, 1)
    }

    func testCLIContextSourceReturnsNoLocalContextWithoutASelfMachine() throws {
        let machinesBody = #"[{"name":"other","self":false}]"#
        let runner = CLIStagedRunner(machines: (machinesBody, "", 0))
        let source = CLIContextSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        let state = try source.context(
            for: .local(session: "shell", path: "~/dev/acme"), settings: settings)

        XCTAssertNil(state)
        XCTAssertEqual(runner.calls.filter { $0.1.first == "run" }.count, 0)
    }

    func testCLIContextSourceReportsCLIFailureLikeAFailedEngineRun() {
        let runner = CLIServiceRunner(result: ("", "no such package", 1))
        let source = CLIContextSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        XCTAssertThrowsError(try source.context(
            for: .remote(alias: "acme-lab", session: "dash"), settings: settings)) { error in
            XCTAssertEqual(error.localizedDescription, "no such package")
        }
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

        let workspaces = try source.workspaces(resolveAlias: { $0 + "-lab" })

        XCTAssertEqual(workspaces, [
            Workspace(name: "alice", alias: "alice-lab"),
            Workspace(name: "bob", alias: "bob-lab"),
        ])
    }

    func testCLIWorkspaceSourceReturnsEmptyOnCLIFailure() throws {
        let runner = CLIServiceRunner(result: ("", "config folder missing", 1))
        let source = CLIWorkspaceSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        XCTAssertEqual(try source.workspaces(resolveAlias: { $0 + "-lab" }), [])
    }

    func testCLIWorkspaceSourceReturnsEmptyOnMalformedJSON() throws {
        let runner = CLIServiceRunner(result: ("not json", "", 0))
        let source = CLIWorkspaceSource(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        XCTAssertEqual(try source.workspaces(resolveAlias: { $0 + "-lab" }), [])
    }

    func testContextFacadeReturnsNoContextForUnsupportedHarnesses() throws {
        let source = FixtureContextSource(state: ContextState(
            cwd: "/home/acme/dev", isClaude: true, updatedAt: "now", plan: nil, prs: [], links: []))
        let facade = ContextFacade(source: source)
        let target = CommandTarget.remote(alias: "acme-devmachine", session: "dash")
        XCTAssertNil(try facade.context(for: target, harnesses: [.codex], settings: settings))
        XCTAssertNil(try facade.context(for: target, harnesses: [], settings: settings))
        XCTAssertEqual(source.calls, [])
        XCTAssertNotNil(try facade.context(for: target, harnesses: [.claude, .codex], settings: settings))
        XCTAssertEqual(source.calls, [target])
    }
}
