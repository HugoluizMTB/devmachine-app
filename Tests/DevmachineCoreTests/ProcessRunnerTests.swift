import XCTest
@testable import DevmachineCore

/// Trava a regressão: `run` NUNCA lança em exit nonzero (devolve stdout),
/// e `runCapturing` separa stdout/stderr/exitCode sem lançar. Um refactor
/// futuro não pode reintroduzir o throw (marcava workspace sem tmux como offline).
final class ProcessRunnerTests: XCTestCase {
    private let runner = ProcessRunner()

    func testRunDevolveStdoutMesmoComExitNonzero() throws {
        let out = try runner.run(
            executable: "/bin/sh",
            args: ["-c", "echo hello; exit 1"],
            environment: nil
        )
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testRunCapturingSeparaStreamsEExitCode() throws {
        let r = try runner.runCapturing(
            executable: "/bin/sh",
            args: ["-c", "echo out; echo err 1>&2; exit 3"],
            environment: nil
        )
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertEqual(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "err")
        XCTAssertEqual(r.exitCode, 3)
    }
}
