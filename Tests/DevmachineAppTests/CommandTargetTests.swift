import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class CapturingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(String, [String])] = []

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        calls.append((executable, args))
        lock.unlock()
        return ("", "", 0)
    }

    var recorded: [(String, [String])] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

final class CommandTargetTests: XCTestCase {
    func testTargetsOfDifferentKindsNeverShareAKey() {
        XCTAssertNotEqual(
            CommandTarget.remote(alias: "acme-devmachine", session: "dash").key,
            CommandTarget.local(path: "/Users/alice/dev/acme").key)
    }

    func testOnlyALocalTargetIsLocal() {
        XCTAssertTrue(CommandTarget.local(path: "/tmp").isLocal)
        XCTAssertFalse(CommandTarget.remote(alias: "a", session: "b").isLocal)
    }

    func testARemoteCommandGoesThroughSSHAndTheSessionFolder() throws {
        let runner = CapturingRunner()
        let host = HostRunner(remote: RemoteService(runner: runner), local: CapturingRunner())

        _ = try host.runCapturing(.remote(alias: "acme-devmachine", session: "dash"), "git status")

        let call = try XCTUnwrap(runner.recorded.first)
        XCTAssertEqual(call.0, "/usr/bin/ssh")
        let command = try XCTUnwrap(call.1.last)
        XCTAssertTrue(command.contains("tmux display -p -t 'dash'"))
        XCTAssertTrue(command.hasSuffix("&& git status"))
    }

    func testALocalCommandRunsHereInTheFolder() throws {
        let local = CapturingRunner()
        let ssh = CapturingRunner()
        let host = HostRunner(remote: RemoteService(runner: ssh), local: local)

        _ = try host.runCapturing(.local(path: "/Users/alice/dev/acme"), "git status")

        XCTAssertTrue(ssh.recorded.isEmpty)
        let call = try XCTUnwrap(local.recorded.first)
        XCTAssertEqual(call.0, "/bin/sh")
        XCTAssertEqual(call.1.first, "-c")
        XCTAssertEqual(call.1.last, "cd '/Users/alice/dev/acme' && git status")
    }

    func testACommandThatCarriesItsOwnPathIsNotWrapped() throws {
        let local = CapturingRunner()
        let host = HostRunner(remote: RemoteService(runner: CapturingRunner()), local: local)

        _ = try host.runCapturingAnywhere(.local(path: "/ignored"), "ls -Ap1 -- '/tmp'")

        XCTAssertEqual(local.recorded.first?.1.last, "ls -Ap1 -- '/tmp'")
    }
}
