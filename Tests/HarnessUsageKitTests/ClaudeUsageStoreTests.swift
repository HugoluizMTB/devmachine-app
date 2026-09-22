import XCTest
@testable import HarnessUsageKit

private final class FakeUsageProvider: UsageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var usageResults: [String]
    private let claudeJSON: String?
    private let stats: UsageStats
    private var _fetchCallCount = 0

    var fetchCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _fetchCallCount
    }

    init(usageResults: [String], claudeJSON: String?, stats: UsageStats) {
        self.usageResults = usageResults
        self.claudeJSON = claudeJSON
        self.stats = stats
    }

    func fetchUsageText() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        _fetchCallCount += 1
        guard !usageResults.isEmpty else {
            return ""
        }
        return usageResults.removeFirst()
    }

    func readClaudeJSON() -> String? {
        claudeJSON
    }

    func computeStats() -> UsageStats {
        stats
    }
}

@MainActor
final class ClaudeUsageStoreTests: XCTestCase {
    private let canonicalUsageText = """
    You are currently using your subscription.

    Current session: 12% used · resets Sep 13 at 12:59pm (America/Recife)
    Current week (all models): 59% used · resets Sep 15 at 12:59pm (America/Recife)
    Current week (Fable): 30% used · resets Sep 15 at 12:59pm (America/Recife)
    """

    private let canonicalClaudeJSON = """
    {"oauthAccount":{"organizationRateLimitTier":"max20x"}}
    """

    private func makeStats() -> UsageStats {
        UsageStats(
            dailyTotals: [DayTokens(date: "2026-09-13", tokens: 100)],
            modelTotals: [ModelTokens(model: "fable", tokens: 100)],
            todayTokens: 100,
            mostUsedModel: "fable"
        )
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testRefreshPopulatesBlocksAndPlanName() async {
        let provider = FakeUsageProvider(
            usageResults: [canonicalUsageText],
            claudeJSON: canonicalClaudeJSON,
            stats: makeStats()
        )
        let store = ClaudeUsageStore(provider: provider)

        store.refresh()
        await waitUntil { store.refreshedAt != nil }

        XCTAssertEqual(store.blocks.count, 3)
        XCTAssertEqual(store.blocks[0].kind, .session)
        XCTAssertEqual(store.blocks[1].kind, .weeklyAll)
        XCTAssertEqual(store.blocks[2].kind, .weeklyModel)
        XCTAssertEqual(store.planName, "max20x")
        XCTAssertNotNil(store.refreshedAt)
        XCTAssertNil(store.errorText)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testRefreshDoesNotRetryOnEmptyResult() async {
        let provider = FakeUsageProvider(
            usageResults: ["", canonicalUsageText],
            claudeJSON: canonicalClaudeJSON,
            stats: makeStats()
        )
        let store = ClaudeUsageStore(provider: provider)

        store.refresh()
        await waitUntil { store.refreshedAt != nil }

        XCTAssertTrue(store.blocks.isEmpty)
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testRefreshSkipsWhileDataIsFresh() async {
        let provider = FakeUsageProvider(
            usageResults: [canonicalUsageText, canonicalUsageText],
            claudeJSON: canonicalClaudeJSON,
            stats: makeStats()
        )
        let store = ClaudeUsageStore(provider: provider)

        store.refresh()
        await waitUntil { store.refreshedAt != nil }
        XCTAssertEqual(provider.fetchCallCount, 1)

        store.refresh()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(provider.fetchCallCount, 1)

        store.refresh(force: true)
        await waitUntil { provider.fetchCallCount == 2 }
        XCTAssertEqual(provider.fetchCallCount, 2)
    }

    func testPollingRunsOnlyWhileObserved() {
        let provider = FakeUsageProvider(
            usageResults: [canonicalUsageText],
            claudeJSON: canonicalClaudeJSON,
            stats: makeStats()
        )
        let store = ClaudeUsageStore(provider: provider)

        XCTAssertFalse(store.isPolling)

        store.beginObserving()
        XCTAssertTrue(store.isPolling)

        store.beginObserving()
        store.endObserving()
        XCTAssertEqual(store.observerCount, 1)
        XCTAssertTrue(store.isPolling)

        store.endObserving()
        XCTAssertEqual(store.observerCount, 0)
        XCTAssertFalse(store.isPolling)

        store.endObserving()
        XCTAssertEqual(store.observerCount, 0)
        XCTAssertFalse(store.isPolling)
    }

    func testRefreshStatsSetsStats() async {
        let expectedStats = makeStats()
        let provider = FakeUsageProvider(
            usageResults: [canonicalUsageText],
            claudeJSON: canonicalClaudeJSON,
            stats: expectedStats
        )
        let store = ClaudeUsageStore(provider: provider)

        store.refreshStats()
        await waitUntil { store.stats != nil }

        XCTAssertEqual(store.stats, expectedStats)
    }
}
