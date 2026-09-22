import XCTest
@testable import HarnessUsageKit

private struct FakeCodexTransport: CodexRPCTransport {
    let snapshot: CodexAccountSnapshot
    func accountSnapshot() throws -> CodexAccountSnapshot { snapshot }
}

final class CodexUsageProviderTests: XCTestCase {
    func testTranslatesMultipleLimitsDailyUsagePlanAndSummary() throws {
        let limits = CodexRateLimitsResponse(
            rateLimits: .init(
                limitId: "fallback", limitName: "Fallback", planType: "plus",
                primary: .init(usedPercent: 1, windowDurationMins: 60, resetsAt: nil),
                secondary: nil),
            rateLimitsByLimitId: [
                "codex": .init(
                    limitId: "codex", limitName: "Codex", planType: "pro",
                    primary: .init(usedPercent: 20, windowDurationMins: 300, resetsAt: 1_790_000_000),
                    secondary: .init(usedPercent: 35, windowDurationMins: 10_080, resetsAt: 1_790_500_000)),
                "review": .init(
                    limitId: "review", limitName: "Review", planType: nil,
                    primary: .init(usedPercent: 5, windowDurationMins: nil, resetsAt: nil),
                    secondary: nil)
            ])
        let usage = CodexUsageResponse(
            summary: .init(
                lifetimeTokens: 1_000, peakDailyTokens: nil, currentStreakDays: 3,
                longestStreakDays: nil, longestRunningTurnSec: 90),
            dailyUsageBuckets: [
                .init(startDate: "2026-09-20", tokens: 100),
                .init(startDate: "2026-09-21", tokens: 250)
            ])
        let provider = CodexUsageProvider(
            transport: FakeCodexTransport(snapshot: .init(rateLimits: limits, usage: usage)),
            now: { Date(timeIntervalSince1970: 1_795_392_000) }) // 2026-11-21 UTC

        let result = try provider.fetchSnapshot(previous: nil)

        XCTAssertEqual(result.planName, "Pro")
        XCTAssertEqual(result.blocks.map(\.percent), [20, 35, 5])
        XCTAssertEqual(result.stats?.dailyTotals.map(\.tokens), [100, 250])
        XCTAssertEqual(result.stats?.modelTotals, [])
        XCTAssertEqual(result.stats?.todayTokens, 0)
        XCTAssertEqual(result.summaryMetrics.map(\.id), ["lifetimeTokens", "currentStreakDays", "longestRunningTurnSec"])
        XCTAssertFalse(result.blocks.contains { $0.resets.hasPrefix("Resets ") })

        let second = try provider.fetchSnapshot(previous: result)
        XCTAssertEqual(second.blocks.map(\.id), result.blocks.map(\.id))
    }

    func testMissingDailyBucketsAndNullableSummaryProduceEmptyOptionalSections() throws {
        let limits = CodexRateLimitsResponse(
            rateLimits: .init(
                limitId: nil, limitName: nil, planType: nil,
                primary: nil, secondary: nil),
            rateLimitsByLimitId: nil)
        let usage = CodexUsageResponse(
            summary: .init(
                lifetimeTokens: nil, peakDailyTokens: nil, currentStreakDays: nil,
                longestStreakDays: nil, longestRunningTurnSec: nil),
            dailyUsageBuckets: nil)
        let provider = CodexUsageProvider(
            transport: FakeCodexTransport(snapshot: .init(rateLimits: limits, usage: usage)))

        let result = try provider.fetchSnapshot(previous: nil)

        XCTAssertNil(result.planName)
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertNil(result.stats)
        XCTAssertTrue(result.summaryMetrics.isEmpty)
    }

    func testTodayUsesMatchingAccountingDateRegardlessOfBucketOrder() throws {
        let today = Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0),
                                 year: 2026, month: 9, day: 22))!
        let limits = CodexRateLimitsResponse(
            rateLimits: .init(limitId: nil, limitName: nil, planType: nil,
                              primary: nil, secondary: nil), rateLimitsByLimitId: nil)
        let usage = CodexUsageResponse(
            summary: .init(lifetimeTokens: nil, peakDailyTokens: nil, currentStreakDays: nil,
                           longestStreakDays: nil, longestRunningTurnSec: nil),
            dailyUsageBuckets: [
                .init(startDate: "2026-09-23", tokens: 300),
                .init(startDate: "2026-09-22", tokens: 220),
                .init(startDate: "2026-09-21", tokens: 100)
            ])
        let provider = CodexUsageProvider(
            transport: FakeCodexTransport(snapshot: .init(rateLimits: limits, usage: usage)),
            now: { today })

        let result = try provider.fetchSnapshot(previous: nil)

        XCTAssertEqual(result.stats?.dailyTotals.map(\.date),
                       ["2026-09-21", "2026-09-22", "2026-09-23"])
        XCTAssertEqual(result.stats?.todayTokens, 220)
    }
}
