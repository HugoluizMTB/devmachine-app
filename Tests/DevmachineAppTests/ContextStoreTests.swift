import XCTest
import Combine
import DevmachineCore
@testable import DevmachineApp

private final class ContextRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var calls = 0

    init(output: String) {
        self.output = output
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        return output
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var invocations: [(String, [String], [String: String]?)] = []

    init(output: String) { self.output = output }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        invocations.append((executable, args, environment))
        lock.unlock()
        return output
    }

    var calls: [(String, [String], [String: String]?)] {
        lock.lock()
        defer { lock.unlock() }
        return invocations
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
final class ContextStoreTests: XCTestCase {
    private let contextJSON = """
    {"cwd":"/home/acme/dev","isClaude":true,"updatedAt":"2026-09-14T01:00:00Z",
     "plan":null,"prs":[],"links":[],"agents":[]}
    """

    func testPollWithSameStateDoesNotRepublish() async throws {
        let runner = ContextRunner(output: contextJSON)
        let store = ContextStore(host: HostRunner(remote: RemoteService(runner: runner)))
        defer { store.stop() }

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { store.state != nil }

        let changes = ChangeCounter()
        let token = store.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        store.poll()
        try await waitUntil { runner.callCount == 2 }
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(changes.count, 0)
        XCTAssertNotNil(store.state)
    }

    func testPollSkipsTickWhileTheSameSessionIsInFlight() async throws {
        let runner = BlockingRunner(output: contextJSON)
        let store = ContextStore(host: HostRunner(remote: RemoteService(runner: runner)))
        defer { store.stop() }

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { runner.callCount == 1 }

        store.poll()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.callCount, 1)

        runner.release()
        try await waitUntil { store.state != nil }

        store.poll()
        runner.release()
        try await waitUntil { runner.callCount == 2 }
    }

    func testALocalTargetRunsTheEngineHereWithTheFolder() async throws {
        let local = RecordingRunner(output: contextJSON)
        let remote = ContextRunner(output: contextJSON)
        let store = ContextStore(
            host: HostRunner(remote: RemoteService(runner: remote), local: local))
        defer { store.stop() }

        store.start(.local(session: "shell", path: "/Users/alice/dev/acme"))
        try await waitUntil { store.state != nil }

        XCTAssertEqual(remote.callCount, 0)
        let call = try XCTUnwrap(local.calls.first)
        XCTAssertEqual(call.0, "/bin/sh")
        let command = try XCTUnwrap(call.1.last)
        XCTAssertTrue(command.contains("/.local/bin/devmachine-infer"))
        XCTAssertTrue(command.hasSuffix("--project '/Users/alice/dev/acme'"))
        XCTAssertNotNil(call.2?["PATH"])
    }

    func testSwitchingFromRemoteToLocalRestartsThePoll() async throws {
        let local = RecordingRunner(output: contextJSON)
        let remote = ContextRunner(output: contextJSON)
        let store = ContextStore(
            host: HostRunner(remote: RemoteService(runner: remote), local: local))
        defer { store.stop() }

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { remote.callCount == 1 }
        store.start(.local(session: "shell", path: "/Users/alice/dev/acme"))
        try await waitUntil { local.calls.count == 1 }
    }

    func testStopClearsStateOnlyOnce() async throws {
        let runner = ContextRunner(output: contextJSON)
        let store = ContextStore(host: HostRunner(remote: RemoteService(runner: runner)))

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { store.state != nil }
        store.stop()

        let changes = ChangeCounter()
        let token = store.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        store.stop()

        XCTAssertNil(store.state)
        XCTAssertEqual(changes.count, 0)
    }
}

@MainActor
final class LocalContextTests: XCTestCase {
    func testTheFolderIsPassedAsTheProjectWithATildeExpanded() {
        let command = LocalContext.command(for: .local(session: "acme", path: "~/dev/acme"))
        XCTAssertTrue(command.hasSuffix("--project '\(NSHomeDirectory())/dev/acme'"))
    }

    func testAHostReadsItsOwnEngineBySessionName() {
        XCTAssertEqual(
            LocalContext.command(for: .remote(alias: "acme-devmachine", session: "dash")),
            "devmachine-infer --session 'dash'")
    }

    func testThePathCarriesTheToolsTheEngineShellsOutTo() {
        let path = LocalContext.environment(home: "/Users/alice")["PATH"] ?? ""
        XCTAssertTrue(path.contains("/Users/alice/.local/bin"))
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/bin"))
    }
}
