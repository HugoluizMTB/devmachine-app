import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Runs the real CLI named by `DEVMACHINE_WIDGETS_E2E` against a temp
/// configuration whose only machine is `here`, this computer (`self: true`),
/// so every command runs on this Mac and never over ssh. Skipped otherwise.
final class WidgetSourceLiveTests: XCTestCase {
    private var config: URL?

    override func tearDown() {
        if let config { try? FileManager.default.removeItem(at: config) }
        config = nil
    }

    private func environment() throws -> SourceRunEnvironment {
        let inherited = ProcessInfo.processInfo.environment
        guard let binary = inherited["DEVMACHINE_WIDGETS_E2E"], !binary.isEmpty else {
            throw XCTSkip("set DEVMACHINE_WIDGETS_E2E to a devmachine binary")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSourceLiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        config = folder
        let file = folder.appendingPathComponent("config.yml")
        try Data("machines:\n  - name: here\n    self: true\n".utf8).write(to: file)
        var variables = inherited
        variables["DEVMACHINE_CONFIG"] = folder.path
        variables["DEVMACHINE_KEYCHAIN"] = "off"
        variables["DEVMACHINE_NO_UPDATE_HINT"] = "1"
        let captured = variables
        return SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: binary, environment: captured) },
            localEnvironment: captured, home: NSHomeDirectory())
    }

    private func request(_ run: String, _ args: [String], _ target: WidgetTarget) -> SourceRunRequest {
        let source = WidgetSource.command(CommandSource(
            run: run, script: nil, args: args, shell: false, target: target,
            every: .interval(60), timeout: 30, mode: .poll, keep: 200, parse: .lines))
        return SourceRunRequest(instanceID: "live", source: ResolvedSource(
            source: source, view: WidgetView(kind: "list"), every: .interval(60), needsApproval: false,
            package: nil, packagePath: nil))
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

    func testTheRealCLIRunsWidgetCommands() async throws {
        let runner = CommandSourceRunner(launcher: FoundationProcessLauncher(), environment: try environment())

        let echoed = try await runner.fetch(request("printf", ["%s\\n", "x; echo INJECTED"], .machine("here")))
        XCTAssertEqual(echoed, .output(.lines(["x; echo INJECTED"])))

        let local = try await runner.fetch(request("printf", ["%s\\n", "$(echo INJECTED)"], .local))
        XCTAssertEqual(local, .output(.lines(["$(echo INJECTED)"])))

        let exited = await failure {
            try await runner.fetch(request("sh", ["-c", "echo oops >&2; exit 3"], .machine("here")))
        }
        guard case let .exited(status, stderr)? = exited else { return XCTFail("\(String(describing: exited))") }
        XCTAssertEqual(status, 3)
        XCTAssertEqual(stderr.split(separator: "\n").first, "oops")

        let ghost = await failure { try await runner.fetch(request("true", [], .machine("ghost"))) }
        guard case let .neverRan(reason)? = ghost else { return XCTFail("\(String(describing: ghost))") }
        XCTAssertTrue(reason.contains("ghost"), reason)
    }

    func testSIGTERMEndsARemoteStream() async throws {
        let (invocation, remote) = try TargetInvoker.invocation(
            .argv(["sleep", "30"]), on: .machine("here"), environment: try environment())
        XCTAssertTrue(remote)
        let process = try FoundationProcessLauncher().launch(invocation) { _ in }
        try await Task.sleep(for: .milliseconds(500))
        let started = Date()
        process.terminate()
        let exit = await process.wait()
        XCTAssertTrue(exit.stoppedByCaller)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
}
