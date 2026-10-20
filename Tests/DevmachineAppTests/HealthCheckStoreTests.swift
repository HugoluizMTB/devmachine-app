import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    private let machinesBody: String
    private var results: [String: (stdout: String, stderr: String, exitCode: Int32)]

    init(machines: String, results: [String: (stdout: String, stderr: String, exitCode: Int32)]) {
        machinesBody = machines
        self.results = results
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(args)
        lock.unlock()
        if args.contains("machines") {
            return (machinesBody, "", 0)
        }
        let key = args.last == "doctor" ? "self" : args.last!
        return results[key] ?? ("", "no fixture for \(key)", 1)
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("condition never became true")
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class HealthCheckStoreTests: XCTestCase {
    func testARefusedDoctorHoldsTheMachineAndTheNextRunDoesNotAskIt() async throws {
        let runner = ScriptedRunner(
            machines: #"[{"name":"box"},{"name":"edge"}]"#,
            results: [
                "box": ("", "alice@203.0.113.7: Permission denied (publickey).", 255),
                "edge": (#"{"checks":[],"ok":true}"#, "", 0),
            ])
        let holds = LoginHoldCenter()
        let store = HealthCheckStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) }, loginHolds: holds)

        store.run()
        try await waitUntil { !store.isRunning && store.results.count == 2 }
        XCTAssertTrue(holds.isHeld(machine: "box"))

        store.run()
        try await waitUntil { !store.isRunning && runner.calls.filter { $0.contains("edge") }.count == 2 }

        XCTAssertEqual(runner.calls.filter { $0.contains("box") }.count, 1)
        let box = try XCTUnwrap(store.results.first { $0.machineName == "box" })
        XCTAssertTrue(box.errorText?.hasPrefix("The server refused the login.") == true)
    }

    func testRunChecksEveryConfiguredMachineGroupedByName() async throws {
        let runner = ScriptedRunner(
            machines: #"[{"name":"mac","self":true},{"name":"box"}]"#,
            results: [
                "self": (#"{"checks":[{"name":"ssh","status":"pass","detail":""}],"ok":true}"#, "", 0),
                "box": (
                    #"{"checks":[{"name":"connection","status":"warn","detail":"stale host key cache"}],"ok":true}"#,
                    "", 0),
            ])
        let store = HealthCheckStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.run()
        try await waitUntil { store.results.count == 2 }

        XCTAssertTrue(runner.calls.contains { $0 == ["--format", "json", "machine", "doctor"] })
        XCTAssertTrue(runner.calls.contains { $0 == ["--format", "json", "doctor", "--machine", "box"] })

        let mac = try XCTUnwrap(store.results.first { $0.machineName == "mac" })
        XCTAssertTrue(mac.isSelf)
        XCTAssertEqual(mac.checks, [DoctorCheck(name: "ssh", status: .pass, detail: "")])

        let box = try XCTUnwrap(store.results.first { $0.machineName == "box" })
        XCTAssertFalse(box.isSelf)
        XCTAssertEqual(box.checks, [DoctorCheck(name: "connection", status: .warn, detail: "stale host key cache")])
        XCTAssertNotNil(store.lastRunAt)
        XCTAssertFalse(store.isRunning)
    }

    func testAMachineThatCouldNotBeReachedGetsItsOwnErrorWithoutFailingTheOthers() async throws {
        let runner = ScriptedRunner(
            machines: #"[{"name":"box"},{"name":"other"}]"#,
            results: [
                "box": ("", "dial tcp: no route to host", 1),
                "other": (#"{"checks":[{"name":"ansible","status":"pass","detail":""}],"ok":true}"#, "", 0),
            ])
        let store = HealthCheckStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: runner) })

        store.run()
        try await waitUntil { store.results.count == 2 }

        let box = try XCTUnwrap(store.results.first { $0.machineName == "box" })
        XCTAssertEqual(box.errorText, "dial tcp: no route to host")
        XCTAssertTrue(box.checks.isEmpty)

        let other = try XCTUnwrap(store.results.first { $0.machineName == "other" })
        XCTAssertNil(other.errorText)
        XCTAssertEqual(other.checks, [DoctorCheck(name: "ansible", status: .pass, detail: "")])
    }

    func testAFailureToListMachinesAtAllSurfacesAsACommandError() async throws {
        struct AlwaysFailsRunner: CommandRunner {
            func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
                throw DevmachineCLIError.commandFailed("devmachine: command not found")
            }
        }
        let store = HealthCheckStore(cli: { DevmachineCLI(executable: "/fake/devmachine", runner: AlwaysFailsRunner()) })

        store.run()
        try await waitUntil { store.commandErrorText != nil }

        XCTAssertEqual(store.commandErrorText, "devmachine: command not found")
        XCTAssertTrue(store.results.isEmpty)
    }
}
