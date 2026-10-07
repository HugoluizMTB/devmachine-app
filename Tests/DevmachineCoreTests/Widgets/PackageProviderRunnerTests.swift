import XCTest
@testable import DevmachineCore

final class PackageProviderRunnerTests: XCTestCase {
    private var launcher: FakeLauncher!
    private let cli = CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: ["SSH_AUTH_SOCK": "/tmp/a"])

    override func setUp() {
        launcher = FakeLauncher()
    }

    override func tearDown() {
        launcher.releaseAll()
    }

    private var environment: SourceRunEnvironment {
        let cli = self.cli
        return SourceRunEnvironment(cli: { cli }, localEnvironment: [:], home: "/Users/alice", isExecutable: { _ in true })
    }

    private func runner(sleep: @escaping SourceSleep = { _ in try await Task.sleep(for: .seconds(3600)) }) -> PackageProviderRunner {
        PackageProviderRunner(launcher: launcher, environment: environment, sleep: sleep)
    }

    private func request(
        target: WidgetTarget = .machine("main"), with: [String: String] = ["window": "5m"],
        returns: [String: String] = ["load": "number", "note": "string?"], needsApproval: Bool = false,
        context: [String: String] = [:], inputs: [String: String] = [:], approvals: WidgetApprovals = WidgetApprovals()
    ) -> SourceRunRequest {
        let source = WidgetSource.packageProvider(PackageProviderSource(
            name: "acme-tools/load", with: with, target: target, every: .interval(30), timeout: 20, returns: returns))
        let resolved = ResolvedSource(
            source: source, view: WidgetView(kind: "number"), every: .interval(30), needsApproval: needsApproval,
            package: "acme-tools", packagePath: nil, inputs: inputs)
        return SourceRunRequest(instanceID: "w", source: resolved, context: context, approvals: approvals)
    }

    private func failure(_ work: () async throws -> SourceRunResult) async -> SourceError? {
        do {
            _ = try await work()
            return nil
        } catch let error as SourceError {
            return error
        } catch {
            XCTFail("unexpected \(error)")
            return nil
        }
    }

    func testItRunsThePackageCommandAndReadsOneObject() async throws {
        launcher.stdout = Data(#"{"load": 0.5}"#.utf8)
        let result = try await runner().fetch(request())
        XCTAssertEqual(result, .output(.json(.object(["load": .double(0.5)]))))
        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/devmachine")
        XCTAssertEqual(invocation.arguments,
                       ["--machine", "main", "run", "--no-log", "--package", "acme-tools", "--", "load", "--window", "5m"])
        XCTAssertEqual(invocation.environment, ["SSH_AUTH_SOCK": "/tmp/a"])
    }

    func testTemplatesAreFilledOnceWithTheAreasContext() async throws {
        launcher.stdout = Data(#"{"load": 1}"#.utf8)
        _ = try await runner().fetch(request(
            target: .workspace("{{context.workspace}}"), with: ["path": "{{inputs.path}}"],
            context: ["workspace": "alice-dev"], inputs: ["path": "{{context.workspace}}; rm -rf ~"]))
        XCTAssertEqual(launcher.invocations.first?.arguments,
                       ["run", "--workspace", "alice-dev", "--no-log", "--package", "acme-tools", "--", "load",
                        "--path", "{{context.workspace}}; rm -rf ~"])
    }

    func testOutputThatIsNotOneObjectIsAnError() async {
        for printed in [#"[1, 2]"#, #"{"load": 1}{"load": 2}"#, "", "  ", #""text""#, "42"] {
            launcher = FakeLauncher()
            launcher.stdout = Data(printed.utf8)
            let error = await failure { try await runner().fetch(request()) }
            guard case .unreadable? = error else { return XCTFail("\(printed): \(String(describing: error))") }
        }
        launcher.stdout = Data("[1]".utf8)
        let list = await failure { try await runner().fetch(request()) }
        XCTAssertEqual(list, .unreadable("acme-tools/load printed JSON that is not one object"))
    }

    func testAMissingDeclaredFieldIsAnError() async throws {
        launcher.stdout = Data(#"{"note": "hi"}"#.utf8)
        let missing = await failure { try await runner().fetch(request()) }
        XCTAssertEqual(missing, .unreadable("acme-tools/load did not print load"))
        launcher = FakeLauncher()
        launcher.stdout = Data(#"{"load": null}"#.utf8)
        let null = await failure { try await runner().fetch(request()) }
        XCTAssertEqual(null, .unreadable("acme-tools/load did not print load"))
        launcher = FakeLauncher()
        launcher.stdout = Data(#"{"load": 2, "extra": true}"#.utf8)
        let ok = try await runner().fetch(request())
        guard case .output(.json) = ok else { return XCTFail("\(ok)") }
    }

    func testALocalTargetNeverStarts() async {
        let error = await failure { try await runner().fetch(request(target: .local)) }
        XCTAssertEqual(error, .refused("a package provider runs on a machine or workspace"))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testATargetThatResolvesToNoNameCannotStart() async {
        let error = await failure { try await runner().fetch(request(target: .machine("{{context.machine}}"))) }
        XCTAssertEqual(error, .cannotStart("the widget's target names no machine or workspace here"))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testItWaitsForApprovalAndRunsNothing() async throws {
        let result = try await runner().fetch(request(needsApproval: true))
        guard case let .needsApproval(.waiting(hash)) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(hash.isEmpty)
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    private func approvals(_ decision: ApprovalDecision) throws -> WidgetApprovals {
        let source = request(needsApproval: true).source
        let hash = try XCTUnwrap(ApprovalSubject.hash(for: source, context: [:]))
        var approvals = WidgetApprovals()
        approvals.record(decision, hash: hash, summary: ApprovalPrompt(source, context: [:]).summary,
                         at: Date(timeIntervalSince1970: 0))
        return approvals
    }

    func testAnAllowedHashRunsOnce() async throws {
        launcher.stdout = Data(#"{"load": 0.5}"#.utf8)
        let result = try await runner().fetch(request(needsApproval: true, approvals: approvals(.allowed)))
        XCTAssertEqual(result, .output(.json(.object(["load": .double(0.5)]))))
        XCTAssertEqual(launcher.invocations.count, 1)
    }

    func testADeniedHashRunsNothing() async throws {
        let result = try await runner().fetch(request(needsApproval: true, approvals: approvals(.denied)))
        guard case let .needsApproval(.denied(hash)) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(hash.isEmpty)
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testExitCodesReadAsTheCLISaysThem() async {
        launcher.status = 3
        launcher.stderr = "boom"
        let exited = await failure { try await runner().fetch(request()) }
        XCTAssertEqual(exited, .exited(status: 3, stderr: "boom"))
        launcher = FakeLauncher()
        launcher.status = 255
        launcher.stderr = "error: acme-tools is not installed on main"
        let never = await failure { try await runner().fetch(request()) }
        XCTAssertEqual(never, .neverRan("acme-tools is not installed on main"))
    }

    func testItStopsAtTheTimeout() async {
        launcher.holds = true
        let error = await failure { try await runner(sleep: { _ in }).fetch(request()) }
        XCTAssertEqual(error, .timedOut(20))
        XCTAssertEqual(launcher.processes.count, 1)
        XCTAssertTrue(try XCTUnwrap(launcher.processes.first).isTerminated)
    }

    func testAWithValueThatHoldsANULByteNeverStarts() async {
        let error = await failure { try await runner().fetch(request(with: ["path": "a\u{0}b"])) }
        XCTAssertEqual(error, .refused("source.with.path holds a NUL byte"))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }
}
