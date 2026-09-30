import XCTest
@testable import DevmachineCore

/// Locks the regression down: `run` NEVER throws on a nonzero exit (it returns
/// stdout), and `runCapturing` splits stdout/stderr/exitCode without throwing. A
/// later refactor must not bring the throw back (it marked a workspace with no
/// tmux as offline).
final class ProcessRunnerTests: XCTestCase {
    private let runner = ProcessRunner()

    func testRunReturnsStdoutEvenOnNonzeroExit() throws {
        let out = try runner.run(
            executable: "/bin/sh",
            args: ["-c", "echo hello; exit 1"],
            environment: nil
        )
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testRunCapturingSplitsStreamsAndExitCode() throws {
        let r = try runner.runCapturing(
            executable: "/bin/sh",
            args: ["-c", "echo out; echo err 1>&2; exit 3"],
            environment: nil
        )
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertEqual(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "err")
        XCTAssertEqual(r.exitCode, 3)
    }

    func testRefusesToSpawnSSHUnderXCTest() {
        XCTAssertThrowsError(try runner.run(
            executable: "/usr/bin/ssh", args: ["acme-devmachine", "true"], environment: nil
        )) { error in
            XCTAssertEqual(error as? ProcessRunnerError, .remoteCommandUnderTest("/usr/bin/ssh"))
        }
    }

    func testRefusesToSpawnMoshClientUnderXCTest() {
        let client = "/Applications/Devmachine.app/Contents/Helpers/mosh-client"
        XCTAssertThrowsError(try runner.run(executable: client, args: ["203.0.113.10", "60001"], environment: nil)) {
            XCTAssertEqual($0 as? ProcessRunnerError, .remoteCommandUnderTest(client))
        }
    }
}
