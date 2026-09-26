import XCTest
import Combine
import DevmachineCore
@testable import DevmachineApp

@MainActor
private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("condition never became true"); return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class ContextStoreTests: XCTestCase {
    private let state = ContextState(
        cwd: "/home/acme/dev", isClaude: true, updatedAt: "now", plan: nil, prs: [], links: [])
    private let remote = CommandTarget.remote(alias: "acme-devmachine", session: "dash")
    private let local = CommandTarget.local(session: "beta", path: "/Users/alice/dev/beta")

    func testDomainSourceStateIsPublishedForTheSelectedTarget() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.state != nil }
        XCTAssertEqual(store.state, state)
        XCTAssertEqual(source.calls, [remote])
    }

    func testPollWithSameStateDoesNotRepublish() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.state != nil }
        let changes = ChangeCounter()
        let token = store.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }
        store.poll()
        try await waitUntil { source.calls.count == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(changes.count, 0)
    }

    func testPollSkipsTickWhileTheSameSessionIsInFlight() async throws {
        let source = FixtureContextSource(state: state, blocked: true)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop(); source.gate?.signal() }
        store.start(remote)
        try await waitUntil { source.calls.count == 1 }
        store.poll()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(source.calls.count, 1)
        source.gate?.signal()
        try await waitUntil { store.state != nil }
        XCTAssertEqual(store.state, state)
    }

    func testSwitchingFromRemoteToLocalRestartsThePoll() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.state != nil }
        store.start(local)
        try await waitUntil { store.state != nil }
        XCTAssertEqual(source.calls, [remote, local])
    }

    func testStoppedPollDoesNotPublishItsLateResult() async throws {
        let source = FixtureContextSource(state: state, blocked: true)
        let store = ContextStore(services: fixtureServices(context: source))
        store.start(remote)
        try await waitUntil { source.calls.count == 1 }
        store.stop()
        source.gate?.signal()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(store.state)
        XCTAssertFalse(store.isPolling)
    }

    func testReturningToTheSameTargetWaitsForItsOldRunAndDiscardsThatResult() async throws {
        let source = FixtureContextSource(state: state, blocked: true)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop(); source.gate?.signal(); source.gate?.signal() }
        store.start(remote)
        try await waitUntil { source.calls.count == 1 }
        store.stop()
        store.start(remote)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(source.calls.count, 1)
        source.gate?.signal()
        try await waitUntil { source.calls.count == 2 }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(store.state)
        source.gate?.signal()
        try await waitUntil { store.state != nil }
    }

    func testStopClearsStateOnlyOnce() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        store.start(remote)
        try await waitUntil { store.state != nil }
        store.stop()
        let changes = ChangeCounter()
        let token = store.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }
        store.stop()
        XCTAssertNil(store.state)
        XCTAssertEqual(changes.count, 0)
    }

    func testUnavailableProviderClearsPreviousContextAndStopsPolling() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        store.start(remote)
        try await waitUntil { store.state != nil }
        store.start(local, harnesses: [.codex])
        XCTAssertNil(store.state)
        XCTAssertFalse(store.isPolling)
        XCTAssertEqual(source.calls, [remote])
    }
}

@MainActor
final class LocalContextTests: XCTestCase {
    func testThePathCarriesTheToolsLocalCommandsShellOutTo() {
        let path = LocalContext.environment(home: "/Users/alice")["PATH"] ?? ""
        XCTAssertTrue(path.contains("/Users/alice/.local/bin"))
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/bin"))
    }
}
