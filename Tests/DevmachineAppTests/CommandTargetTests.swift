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
            CommandTarget.local(session: "shell", path: "/Users/alice/dev/acme").key)
    }

    func testOnlyALocalTargetIsLocal() {
        XCTAssertTrue(CommandTarget.local(session: "shell", path: "/tmp").isLocal)
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

        _ = try host.runCapturing(.local(session: "shell", path: "/Users/alice/dev/acme"), "git status")

        XCTAssertTrue(ssh.recorded.isEmpty)
        let call = try XCTUnwrap(local.recorded.first)
        XCTAssertEqual(call.0, "/bin/sh")
        XCTAssertEqual(call.1.first, "-c")
        XCTAssertEqual(call.1.last, "cd '/Users/alice/dev/acme' && git status")
    }

    func testACommandThatCarriesItsOwnPathIsNotWrapped() throws {
        let local = CapturingRunner()
        let host = HostRunner(remote: RemoteService(runner: CapturingRunner()), local: local)

        _ = try host.runCapturingAnywhere(.local(session: "shell", path: "/ignored"), "ls -Ap1 -- '/tmp'")

        XCTAssertEqual(local.recorded.first?.1.last, "ls -Ap1 -- '/tmp'")
    }

    func testTypingGoesThroughTmuxOnAHost() throws {
        let ssh = CapturingRunner()
        let host = HostRunner(remote: RemoteService(runner: ssh), local: CapturingRunner())

        try host.type("src/main.swift", into: .remote(alias: "acme-devmachine", session: "dash"))

        let command = try XCTUnwrap(ssh.recorded.first?.1.last)
        XCTAssertTrue(command.hasPrefix("tmux send-keys -t 'dash' --"))
        XCTAssertTrue(command.contains("src/main.swift"))
        XCTAssertFalse(command.hasSuffix("Enter"))
    }

    func testSendingAddsTheReturnKeyOnAHost() throws {
        let ssh = CapturingRunner()
        let host = HostRunner(remote: RemoteService(runner: ssh), local: CapturingRunner())

        try host.send("/eoq", into: .remote(alias: "acme-devmachine", session: "dash"))

        XCTAssertTrue(try XCTUnwrap(ssh.recorded.first?.1.last).hasSuffix("Enter"))
    }

    func testTypingLocallyGoesThroughTheLocalMultiplexer() throws {
        let local = CapturingRunner()
        let host = HostRunner(remote: RemoteService(runner: CapturingRunner()), local: local)

        try host.type("src/main.swift", into: .local(session: "acme", path: "/tmp"))

        // Without zmx in the bundle (tests run outside the app) nothing is run,
        // and nothing is expected to crash either.
        for call in local.recorded {
            XCTAssertTrue(call.1.first == "send")
            XCTAssertEqual(call.1.last, "src/main.swift")
        }
    }

    func testTheEnterTextIsACarriageReturn() {
        XCTAssertEqual(Zmx.enterText, "\r")
        XCTAssertEqual(
            Zmx.sendArguments(name: "acme", text: "hi"), ["send", "acme", "hi"])
    }

    func testAHostTargetHasNoSessionAndReadsAsItsAlias() {
        let target = CommandTarget.host(alias: "acme-devmachine")
        XCTAssertEqual(target.session, "")
        XCTAssertEqual(target.label, "acme-devmachine")
        XCTAssertEqual(CommandTarget.local(session: "acme", path: "/tmp").label, "acme")
    }
}
