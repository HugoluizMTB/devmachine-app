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

    private func isGone(_ pid: pid_t) async throws -> Bool {
        for _ in 0..<40 {
            if kill(pid, 0) != 0, errno == ESRCH { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    func testTheGraceKillTakesTheChildrenOfAShellThatIgnoresSIGTERM() async throws {
        let box = Box()
        let process = try FoundationProcessLauncher(killGrace: 0.2).launch(
            ProcessInvocation(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; /bin/sleep 47 & echo $!; wait"])) { box.append($0) }
        var grandchild: pid_t?
        for _ in 0..<40 where grandchild == nil {
            grandchild = pid_t(box.text.trimmingCharacters(in: .whitespacesAndNewlines))
            if grandchild == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        let sleeper = try XCTUnwrap(grandchild)
        process.terminate()
        let exit = await process.wait()
        XCTAssertTrue(exit.stoppedByCaller)
        let gone = try await isGone(sleeper)
        if !gone { kill(sleeper, SIGKILL) }
        XCTAssertTrue(gone)
    }

    func testAForcedFinishClosesThePipesALeftoverChildHolds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("wrote").path
        let process = try FoundationProcessLauncher().launch(
            ProcessInvocation(executable: "/bin/sh", arguments: [
                "-c", "(/bin/sleep 2; echo late && /usr/bin/touch \"$1\") & exit 0", "sh", marker,
            ])) { _ in }
        let exit = await process.wait()
        XCTAssertEqual(exit.status, 0)
        try await Task.sleep(for: .seconds(2.5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }

    func testRefusesSSHUnderTests() {
        XCTAssertThrowsError(try FoundationProcessLauncher().launch(
            ProcessInvocation(executable: "/usr/bin/ssh", arguments: ["acme-devmachine"])) { _ in })
        XCTAssertThrowsError(try FoundationProcessLauncher().launch(
            ProcessInvocation(executable: "/usr/bin/env", arguments: ["ssh", "acme-devmachine"])) { _ in })
    }
}
