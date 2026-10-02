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

    func testASessionReadBeforeShowsItsContextAtOnceWhileItReadsAgain() async throws {
        let cache = DataCache()
        let first = ContextStore(services: fixtureServices(context: FixtureContextSource(state: state)), cache: cache)
        first.start(remote)
        try await waitUntil { first.state != nil }
        first.stop()

        let source = FixtureContextSource(state: state, blocked: true)
        let store = ContextStore(services: fixtureServices(context: source), cache: cache)
        defer { store.stop() }
        store.start(remote)

        XCTAssertEqual(store.state, state)
        XCTAssertFalse(store.showsSkeleton)
        XCTAssertEqual(store.status, .loaded)
        XCTAssertNotNil(store.stateReadAt)
        try await waitUntil { source.calls.count == 1 }
        source.gate?.signal()
        try await waitUntil { store.stateReadAt == nil }
    }

    func testSwitchingBackToASessionNeverBlanksItsContext() async throws {
        let other = ContextState(cwd: "/Users/alice/dev/beta", isClaude: true, updatedAt: "now", plan: nil, prs: [], links: [])
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source), cache: DataCache())
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.state == state }
        source.state = other
        store.start(local)
        try await waitUntil { store.state == other }

        store.start(remote)

        XCTAssertEqual(store.state, state)
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
        store.start(local, harnesses: [HarnessID(rawValue: "aider")])
        XCTAssertNil(store.state)
        XCTAssertFalse(store.isPolling)
        XCTAssertEqual(source.calls, [remote])
    }

    func testTheFirstReadIsLoadingUntilItAnswers() async throws {
        let source = FixtureContextSource(state: state, blocked: true)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop(); source.gate?.signal() }
        XCTAssertEqual(store.status, .idle)
        store.start(remote)
        XCTAssertEqual(store.status, .loading)
        source.gate?.signal()
        try await waitUntil { store.status == .loaded }
        XCTAssertEqual(store.state, state)
    }

    func testTheSkeletonShowsOnlyUntilTheFirstReadAnswers() async throws {
        let source = FixtureContextSource(state: state, blocked: true)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop(); source.gate?.signal() }
        XCTAssertFalse(store.showsSkeleton)
        store.start(remote)
        XCTAssertTrue(store.showsSkeleton)
        source.gate?.signal()
        try await waitUntil { store.status == .loaded }
        XCTAssertFalse(store.showsSkeleton)
    }

    func testAFailedFirstReadShowsTheErrorNotTheSkeleton() async throws {
        let source = FixtureContextSource(failure: DevmachineCLIError.commandFailed("timeout"))
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status != .loading }
        XCTAssertFalse(store.showsSkeleton)
    }

    func testAnEmptyAnswerShowsTheEmptyStateNotTheSkeleton() async throws {
        let source = FixtureContextSource(state: nil)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status == .empty }
        XCTAssertFalse(store.showsSkeleton)
    }

    func testARefreshAfterContextArrivedNeverBringsTheSkeletonBack() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status == .loaded }
        store.poll()
        XCTAssertFalse(store.showsSkeleton)
        store.retry()
        XCTAssertFalse(store.showsSkeleton)
    }

    func testAnEngineWithNothingToSayIsEmptyNotLoading() async throws {
        let source = FixtureContextSource(state: nil)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status == .empty }
        XCTAssertNil(store.state)
    }

    func testAFailedReadSaysWhy() async throws {
        let source = FixtureContextSource(failure: DevmachineCLIError.commandFailed("ssh: host unreachable\n"))
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status != .loading }
        XCTAssertEqual(store.status, .failed("ssh: host unreachable"))
        XCTAssertNil(store.state)
    }

    func testAnUnreadableAnswerIsNamedPlainly() async throws {
        let bad = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "junk"))
        let source = FixtureContextSource(failure: bad)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status != .loading }
        XCTAssertEqual(store.status, .failed(ContextLoadStatus.unreadableAnswer))
    }

    func testAFailedRefreshKeepsTheLastContextOnScreen() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status == .loaded }
        source.failure = DevmachineCLIError.commandFailed("timeout")
        store.poll()
        try await waitUntil { store.status == .failed("timeout") }
        XCTAssertEqual(store.state, state)
    }

    func testRetryAfterAFailureLoadsAgain() async throws {
        let source = FixtureContextSource(state: state, failure: DevmachineCLIError.commandFailed("timeout"))
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status == .failed("timeout") }
        source.failure = nil
        store.retry()
        XCTAssertEqual(store.status, .loading)
        try await waitUntil { store.status == .loaded }
        XCTAssertEqual(store.state, state)
    }

    func testRetryOverStaleContextKeepsTheFailureUntilTheReadAnswers() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.start(remote)
        try await waitUntil { store.status == .loaded }
        source.failure = DevmachineCLIError.commandFailed("timeout")
        store.poll()
        try await waitUntil { store.status == .failed("timeout") }
        source.failure = nil
        store.retry()
        XCTAssertEqual(store.status, .failed("timeout"))
        try await waitUntil { store.status == .loaded }
    }

    func testStopGoesBackToIdle() async throws {
        let source = FixtureContextSource(state: state)
        let store = ContextStore(services: fixtureServices(context: source))
        store.start(remote)
        try await waitUntil { store.status == .loaded }
        store.stop()
        XCTAssertEqual(store.status, .idle)
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
