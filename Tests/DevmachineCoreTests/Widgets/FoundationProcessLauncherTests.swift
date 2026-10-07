import XCTest
@testable import DevmachineCore

final class FoundationProcessLauncherTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Data()
        func append(_ data: Data) { lock.withLock { stored.append(data) } }
        var text: String { lock.withLock { String(decoding: stored, as: UTF8.self) } }
    }

    func testCollectsStdoutStderrAndStatus() async throws {
        let box = Box()
        let process = try FoundationProcessLauncher().launch(
            ProcessInvocation(executable: "/bin/sh", arguments: ["-c", "printf 'a\\nb'; printf oops >&2; exit 3"])) { box.append($0) }
        let exit = await process.wait()
        XCTAssertEqual(exit.status, 3)
        XCTAssertEqual(exit.stderr, "oops")
        XCTAssertFalse(exit.stoppedByCaller)
        XCTAssertEqual(box.text, "a\nb")
    }

    func testStdinIsEmpty() async throws {
        let process = try FoundationProcessLauncher().launch(ProcessInvocation(executable: "/bin/cat", arguments: [])) { _ in }
        let exit = await process.wait()
        XCTAssertEqual(exit.status, 0)
    }

    func testStderrIsCappedAt16KB() async throws {
        let process = try FoundationProcessLauncher().launch(
            ProcessInvocation(executable: "/bin/sh", arguments: ["-c", "head -c 40000 /dev/zero | tr '\\0' e >&2"])) { _ in }
        let exit = await process.wait()
        XCTAssertEqual(exit.stderr.utf8.count, LaunchedProcess.maxStderr)
    }

    func testTerminateStopsALongRunningProcess() async throws {
        let process = try FoundationProcessLauncher().launch(ProcessInvocation(executable: "/bin/sleep", arguments: ["30"])) { _ in }
        let started = Date()
        process.terminate()
        let exit = await process.wait()
        XCTAssertTrue(exit.stoppedByCaller)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testAProcessThatIgnoresSIGTERMIsKilledAfterTheGrace() async throws {
        let process = try FoundationProcessLauncher(killGrace: 0.2).launch(
            ProcessInvocation(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; exec /bin/sleep 30"])) { _ in }
        try await Task.sleep(for: .milliseconds(200))
        let started = Date()
        process.terminate()
        let exit = await process.wait()
        XCTAssertTrue(exit.stoppedByCaller)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testRefusesSSHUnderTests() {
        XCTAssertThrowsError(try FoundationProcessLauncher().launch(
            ProcessInvocation(executable: "/usr/bin/ssh", arguments: ["acme-devmachine"])) { _ in })
        XCTAssertThrowsError(try FoundationProcessLauncher().launch(
            ProcessInvocation(executable: "/usr/bin/env", arguments: ["ssh", "acme-devmachine"])) { _ in })
    }
}
