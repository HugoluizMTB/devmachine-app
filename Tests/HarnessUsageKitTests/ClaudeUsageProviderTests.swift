import XCTest
@testable import HarnessUsageKit

private final class CountingClaudeSource: UsageProvider, @unchecked Sendable {
    var usageError: Error?
    var statsValues: [UsageStats]
    private(set) var statsCalls = 0

    init(usageError: Error? = nil, statsValues: [UsageStats]) {
        self.usageError = usageError
        self.statsValues = statsValues
    }

    func fetchUsageText() throws -> String {
        if let usageError { throw usageError }
        return "Current session: 12% used"
    }
    func readClaudeJSON() -> String? { nil }
    func computeStats() -> UsageStats {
        let index = min(statsCalls, statsValues.count - 1)
        statsCalls += 1
        return statsValues[index]
    }
}

private enum ClaudeSourceError: Error { case unavailable }

private final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

final class ClaudeUsageProviderTests: XCTestCase {
    private func stats(_ tokens: Int64) -> UsageStats {
        UsageStats(dailyTotals: [], modelTotals: [], todayTokens: tokens, mostUsedModel: nil)
    }

    func testStatisticsKeepIndependentFiveMinuteCadence() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let source = CountingClaudeSource(statsValues: [stats(10), stats(20)])
        let provider = ClaudeUsageProvider(
            provider: source, statsPollSeconds: 300, now: { clock.date })

        XCTAssertEqual(try provider.fetchSnapshot(previous: nil).stats?.todayTokens, 10)
        clock.date = clock.date.addingTimeInterval(60)
        XCTAssertEqual(try provider.fetchSnapshot(previous: nil).stats?.todayTokens, 10)
        XCTAssertEqual(source.statsCalls, 1)
        clock.date = clock.date.addingTimeInterval(241)
        XCTAssertEqual(try provider.fetchSnapshot(previous: nil).stats?.todayTokens, 20)
        XCTAssertEqual(source.statsCalls, 2)
    }

    func testStatisticsStillUpdateWhenUsageCommandFails() throws {
        let source = CountingClaudeSource(
            usageError: ClaudeSourceError.unavailable, statsValues: [stats(42)])
        let provider = ClaudeUsageProvider(provider: source)

        let result = try provider.fetchSnapshot(previous: nil)

        XCTAssertEqual(result.stats?.todayTokens, 42)
        XCTAssertTrue(result.blocks.isEmpty)
    }
}
