import XCTest
@testable import HarnessUsageKit

private enum FakeUsageError: Error { case failed }

private final class FakeHarnessUsageProvider: HarnessUsageProvider, @unchecked Sendable {
    private let lock = NSLock()
    let harnessID: String
    var result: Result<HarnessUsageSnapshot, Error>
    var delay: TimeInterval
    private(set) var calls = 0

    init(
        id: String,
        result: Result<HarnessUsageSnapshot, Error>,
        delay: TimeInterval = 0
    ) {
        harnessID = id
        self.result = result
        self.delay = delay
    }

    func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot {
        lock.lock()
        calls += 1
        let result = result
        let delay = delay
        lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return try result.get()
    }
}

@MainActor
final class HarnessUsageStoreTests: XCTestCase {
    private func snapshot(plan: String? = nil, percent: Int = 10) -> HarnessUsageSnapshot {
        HarnessUsageSnapshot(
            planName: plan,
            blocks: [UsageBlock(kind: .session, label: "Session", percent: percent, resets: "Soon")],
            stats: nil,
            summaryMetrics: [])
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testStatesKeepProviderOrderAndFailuresStayIndependent() async {
        let first = FakeHarnessUsageProvider(id: "first", result: .success(snapshot(plan: "Pro")))
        let second = FakeHarnessUsageProvider(id: "second", result: .failure(FakeUsageError.failed))
        let store = HarnessUsageStore(providers: [first, second])

        store.refresh(force: true)
        await waitUntil { store.states.allSatisfy { !$0.isLoading } }

        XCTAssertEqual(store.states.map(\.harnessID), ["first", "second"])
        XCTAssertEqual(store.state(for: "first")?.snapshot?.planName, "Pro")
        XCTAssertNil(store.state(for: "first")?.errorText)
        XCTAssertNotNil(store.state(for: "second")?.errorText)
    }

    func testRefreshDoesNotOverlapForOneProvider() async {
        let provider = FakeHarnessUsageProvider(
            id: "slow", result: .success(snapshot()), delay: 0.15)
        let store = HarnessUsageStore(providers: [provider])

        store.refresh(force: true)
        store.refresh(force: true)
        await waitUntil { store.state(for: "slow")?.refreshedAt != nil }

        XCTAssertEqual(provider.calls, 1)
    }

    func testPollingLivesWhileAtLeastOneSurfaceObserves() {
        let store = HarnessUsageStore(providers: [])

        store.beginObserving()
        store.beginObserving()
        store.endObserving()
        XCTAssertTrue(store.isPolling)
        XCTAssertEqual(store.observerCount, 1)

        store.endObserving()
        XCTAssertFalse(store.isPolling)
        XCTAssertEqual(store.observerCount, 0)
    }

    func testIdenticalSnapshotDoesNotReplaceTheSnapshotValue() async {
        let value = snapshot(percent: 25)
        let provider = FakeHarnessUsageProvider(id: "same", result: .success(value))
        let store = HarnessUsageStore(providers: [provider])

        store.refresh(force: true)
        await waitUntil { store.state(for: "same")?.refreshedAt != nil }
        let first = store.state(for: "same")?.snapshot

        store.refresh(force: true)
        await waitUntil { provider.calls == 2 && store.state(for: "same")?.isLoading == false }

        XCTAssertEqual(store.state(for: "same")?.snapshot, first)
    }

    func testReconfigurationDiscardsResultFromRemovedProvider() async {
        let old = FakeHarnessUsageProvider(
            id: "same", result: .success(snapshot(plan: "Old")), delay: 0.15)
        let replacement = FakeHarnessUsageProvider(
            id: "same", result: .success(snapshot(plan: "New")))
        let store = HarnessUsageStore(providers: [old])

        store.refresh(force: true)
        store.configure(providers: [replacement])
        store.refresh(force: true)
        await waitUntil { store.state(for: "same")?.snapshot?.planName == "New" }
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.state(for: "same")?.snapshot?.planName, "New")
    }
    func testTheCardSkeletonShowsUntilTheFirstSnapshotArrives() async {
        let provider = FakeHarnessUsageProvider(id: "claude", result: .success(snapshot()), delay: 0.2)
        let store = HarnessUsageStore(providers: [provider])
        XCTAssertEqual(store.state(for: "claude")?.showsSkeleton, true)

        store.refresh(force: true)
        XCTAssertEqual(store.state(for: "claude")?.showsSkeleton, true)
        await waitUntil { store.state(for: "claude")?.snapshot != nil }

        XCTAssertEqual(store.state(for: "claude")?.showsSkeleton, false)
    }

    func testAFailedFirstFetchShowsTheErrorNotTheSkeleton() async {
        let provider = FakeHarnessUsageProvider(id: "claude", result: .failure(FakeUsageError.failed))
        let store = HarnessUsageStore(providers: [provider])

        store.refresh(force: true)
        await waitUntil { store.state(for: "claude")?.errorText != nil }

        XCTAssertEqual(store.state(for: "claude")?.showsSkeleton, false)
    }

    func testARefreshAfterASnapshotNeverBringsTheSkeletonBack() async {
        let provider = FakeHarnessUsageProvider(id: "claude", result: .success(snapshot()))
        let store = HarnessUsageStore(providers: [provider])
        store.refresh(force: true)
        await waitUntil { store.state(for: "claude")?.snapshot != nil }

        provider.delay = 0.2
        store.refresh(force: true)

        XCTAssertEqual(store.state(for: "claude")?.isLoading, true)
        XCTAssertEqual(store.state(for: "claude")?.showsSkeleton, false)
    }

    func testRefreshingOneHarnessLeavesTheOthersAlone() async {
        let first = FakeHarnessUsageProvider(id: "first", result: .success(snapshot()))
        let second = FakeHarnessUsageProvider(id: "second", result: .success(snapshot()))
        let store = HarnessUsageStore(providers: [first, second])

        store.refresh(harnessID: "second", force: true)
        store.refresh(harnessID: "missing", force: true)
        await waitUntil { store.state(for: "second")?.refreshedAt != nil }

        XCTAssertEqual(first.calls, 0)
        XCTAssertEqual(second.calls, 1)
    }
}
