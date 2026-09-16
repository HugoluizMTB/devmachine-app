import XCTest
import Combine
import DevmachineCore
@testable import DevmachineApp

private final class GitRunner: CommandRunner, @unchecked Sendable {
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
final class GitStoreTests: XCTestCase {
    private let snapshotOutput = """
    /home/alice/dev/dash
    # branch.oid 1a2b3c4d5e6f7a8b
    # branch.head main
    # branch.upstream origin/main
    # branch.ab +1 -0
    1 .M N... 100644 100644 100644 aaa bbb Sources/App.swift
    \u{1e}
    worktree /home/alice/dev/dash
    HEAD 1a2b3c4d5e6f7a8b
    branch refs/heads/main
    \u{1e}
    1a2b3c4\u{1f}Add the git tab\u{1f}alice\u{1f}2 hours ago\u{1f}HEAD -> main
    """

    func testStartReadsTheSnapshot() async throws {
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: GitRunner(output: snapshotOutput))))
        defer { store.stop() }

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { store.snapshot != nil }

        let snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertEqual(snapshot.upstream, "origin/main")
        XCTAssertEqual(snapshot.ahead, 1)
        XCTAssertEqual(snapshot.dirtyFiles, 1)
        XCTAssertEqual(snapshot.commits.first?.refs, ["main"])
        XCTAssertNil(store.errorText)
        XCTAssertFalse(store.isLoading)
    }

    func testRefreshWithTheSameOutputDoesNotRepublish() async throws {
        let runner = GitRunner(output: snapshotOutput)
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: runner)))
        defer { store.stop() }

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { store.snapshot != nil }

        let changes = ChangeCounter()
        let token = store.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        store.refresh()
        try await waitUntil { runner.callCount == 2 }
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(changes.count, 0)
        XCTAssertNotNil(store.snapshot)
    }

    func testRefreshSkipsTheTickWhileTheSameSessionIsInFlight() async throws {
        let runner = BlockingRunner(output: snapshotOutput)
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: runner)))
        defer { store.stop() }

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { runner.callCount == 1 }
        XCTAssertTrue(store.isLoading)

        store.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.callCount, 1)

        runner.release()
        try await waitUntil { store.snapshot != nil }
        XCTAssertFalse(store.isLoading)
    }

    func testStopClearsTheSnapshot() async throws {
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: GitRunner(output: snapshotOutput))))

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { store.snapshot != nil }
        store.stop()

        XCTAssertNil(store.snapshot)

        let changes = ChangeCounter()
        let token = store.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        store.stop()
        XCTAssertEqual(changes.count, 0)
    }

    func testOutputWithoutARepositoryLeavesNoSnapshotAndNoError() async throws {
        let runner = GitRunner(output: "")
        let store = GitStore(host: HostRunner(remote: RemoteService(runner: runner)))
        defer { store.stop() }

        store.start(.remote(alias: "acme-devmachine", session: "dash"))
        try await waitUntil { runner.callCount == 1 && !store.isLoading }

        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.errorText)
    }
}
