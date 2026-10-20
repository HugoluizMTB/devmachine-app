import XCTest
@testable import DevmachineCore

private final class FakeCLIRunner: CommandRunner, @unchecked Sendable {
    var result: (stdout: String, stderr: String, exitCode: Int32) = ("", "", 0)
    var launchError: Error?
    private(set) var receivedInput: Data?

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        if let launchError { throw launchError }
        return result
    }

    func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        receivedInput = input
        return try runCapturing(executable: executable, args: args, environment: environment)
    }
}

private struct ThrowingRunRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        throw LaunchFailure()
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        ("", "", 0)
    }
}

private struct LaunchFailure: LocalizedError {
    var errorDescription: String? { "no such file" }
}

final class LoggingCommandRunnerTests: XCTestCase {
    private var directory: URL!
    private var logger: AppLogger!
    private var inner: FakeCLIRunner!
    private var runner: LoggingCommandRunner!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("clilog-\(UUID().uuidString)")
        logger = AppLogger(directory: directory)
        inner = FakeCLIRunner()
        runner = LoggingCommandRunner(wrapping: inner, logger: logger)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var log: String {
        logger.flush()
        return (try? String(contentsOf: directory.appendingPathComponent("app.log"), encoding: .utf8)) ?? ""
    }

    func testFailureLogsRedactedArgumentsExitCodeDurationAndStderrTail() throws {
        let stderr = (1...30).map { "line \($0)" }.joined(separator: "\n")
            + "\nauth failed for token=fake-stderr-token\n"
        inner.result = ("", stderr, 2)
        let result = try runner.runCapturing(
            executable: "/opt/homebrew/bin/devmachine",
            args: ["machines", "add", "main", "--host", "203.0.113.10", "--token", "fake-arg-token"],
            environment: nil)
        XCTAssertEqual(result.exitCode, 2)
        let text = log
        XCTAssertTrue(text.contains("ERROR [cli] devmachine machines add main --host 203.0.113.10 --token ***: exit 2 in "),
                      text)
        XCTAssertTrue(text.range(of: #"in \d+\.\d\ds"#, options: .regularExpression) != nil, text)
        XCTAssertTrue(text.contains("    | auth failed for token=***"), text)
        XCTAssertTrue(text.contains("    | line 30"), text)
        XCTAssertFalse(text.contains("    | line 11\n"), text)
        XCTAssertFalse(text.contains("fake-arg-token"))
        XCTAssertFalse(text.contains("fake-stderr-token"))
    }

    func testPasswordOnStdinNeverAppears() throws {
        let password = "fake-stdin-password-0123"
        _ = try runner.runCapturing(
            executable: "/opt/homebrew/bin/devmachine", args: ["machines", "add", "main", "--password-stdin"],
            environment: nil, input: Data(password.utf8), onBytesWritten: nil)
        XCTAssertEqual(inner.receivedInput, Data(password.utf8))
        let text = log
        XCTAssertFalse(text.contains(password))
        XCTAssertTrue(text.contains("devmachine machines add main --password-stdin (stdin): exit 0"), text)
    }

    func testAPasswordTheCommandPrintsBackIsHidden() throws {
        inner.result = ("", "login failed for password fake-echoed-password-0123\n", 1)
        _ = try runner.runCapturing(
            executable: "/opt/homebrew/bin/devmachine", args: ["machines", "add", "main", "--password-stdin"],
            environment: nil, input: Data("fake-echoed-password-0123\n".utf8), onBytesWritten: nil)
        let text = log
        XCTAssertFalse(text.contains("fake-echoed-password-0123"), text)
        XCTAssertTrue(text.contains("    | login failed for password ***"), text)
    }

    func testRunKeepsTheInnerRunnersErrors() {
        let throwing = LoggingCommandRunner(wrapping: ThrowingRunRunner(), logger: logger)
        XCTAssertThrowsError(try throwing.run(executable: "/opt/homebrew/bin/devmachine", args: ["sync"], environment: nil))
        XCTAssertTrue(log.contains("ERROR [cli] devmachine sync: did not start: no such file"), log)
    }

    func testSecretsSetValueNeverAppears() throws {
        _ = try runner.runCapturing(
            executable: "/usr/local/bin/devmachine", args: ["secrets", "set", "API_TOKEN", "fake-value-0123"],
            environment: nil)
        XCTAssertFalse(log.contains("fake-value-0123"))
    }

    func testLaunchFailureIsLoggedAndRethrown() {
        inner.launchError = LaunchFailure()
        XCTAssertThrowsError(try runner.runCapturing(
            executable: "/opt/homebrew/bin/devmachine", args: ["version"], environment: nil))
        XCTAssertTrue(log.contains("ERROR [cli] devmachine version: did not start: no such file"), log)
    }

    func testPolledReadSuccessIsQuiet() throws {
        _ = try runner.runCapturing(
            executable: "/opt/homebrew/bin/devmachine", args: ["--format", "json", "config", "show"], environment: nil)
        XCTAssertFalse(log.contains("config show"))
    }

    func testStderrLinesStillReachTheCaller() throws {
        inner.result = ("", "one\ntwo", 0)
        let seen = LockedLines()
        _ = try runner.runCapturing(
            executable: "/opt/homebrew/bin/devmachine", args: ["sync"], environment: nil,
            onStderrLine: { seen.append($0) })
        XCTAssertEqual(seen.lines, ["one", "two"])
    }
}

private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var lines: [String] { lock.withLock { stored } }
    func append(_ line: String) { lock.withLock { stored.append(line) } }
}

final class CLICallTests: XCTestCase {
    func testPolledReadsAreTheCommandsTheAppRunsOnATimer() {
        let polled: [[String]] = [
            ["--format", "json", "sessions", "--workspace", "acme"],
            ["run", "--machine", "main", "--package", "devmachine-app", "--", "stats"],
            ["widgets", "list", "--format", "json"],
            ["packages", "outdated", "--format", "json"],
            ["--format", "json", "config", "show"],
            ["--format", "json", "config", "path"],
            ["--format", "json", "workspaces", "list"],
            ["--format", "json", "machines", "list"],
            ["--format", "json", "aliases"],
            ["version"],
            ["--machine", "main", "--format", "json", "expose", "list"],
            ["--format", "json", "machine", "doctor"],
            ["--format", "json", "scheduled", "list"],
        ]
        for args in polled {
            XCTAssertTrue(CLICall.isPolledRead(args), args.joined(separator: " "))
        }
        let actions: [[String]] = [
            ["machines", "add", "main"], ["machines", "rm", "main", "--yes"], ["secrets", "set", "NAME"],
            ["--format", "json", "expose", "add", "acme", "3000", "--host", "app.example.com"], ["sync"],
            ["setup", "--machine", "main"],
        ]
        for args in actions {
            XCTAssertFalse(CLICall.isPolledRead(args), args.joined(separator: " "))
        }
    }
}
