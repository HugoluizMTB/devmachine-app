import Foundation

public struct CodexAccountSnapshot: Equatable, Sendable {
    public let rateLimits: CodexRateLimitsResponse
    public let usage: CodexUsageResponse

    public init(rateLimits: CodexRateLimitsResponse, usage: CodexUsageResponse) {
        self.rateLimits = rateLimits
        self.usage = usage
    }
}

public struct CodexRateLimitsResponse: Codable, Equatable, Sendable {
    public let rateLimits: CodexRateLimitSnapshot
    public let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?

    public init(
        rateLimits: CodexRateLimitSnapshot,
        rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }
}

public struct CodexRateLimitSnapshot: Codable, Equatable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let planType: String?
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?

    public init(
        limitId: String?, limitName: String?, planType: String?,
        primary: CodexRateLimitWindow?, secondary: CodexRateLimitWindow?
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
    }
}

public struct CodexRateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int64?
    public let resetsAt: Int64?

    public init(usedPercent: Int, windowDurationMins: Int64?, resetsAt: Int64?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct CodexUsageResponse: Codable, Equatable, Sendable {
    public let summary: CodexUsageSummary
    public let dailyUsageBuckets: [CodexDailyUsageBucket]?

    public init(summary: CodexUsageSummary, dailyUsageBuckets: [CodexDailyUsageBucket]?) {
        self.summary = summary
        self.dailyUsageBuckets = dailyUsageBuckets
    }
}

public struct CodexDailyUsageBucket: Codable, Equatable, Sendable {
    public let startDate: String
    public let tokens: Int64

    public init(startDate: String, tokens: Int64) {
        self.startDate = startDate
        self.tokens = tokens
    }
}

public struct CodexUsageSummary: Codable, Equatable, Sendable {
    public let lifetimeTokens: Int64?
    public let peakDailyTokens: Int64?
    public let currentStreakDays: Int64?
    public let longestStreakDays: Int64?
    public let longestRunningTurnSec: Int64?

    public init(
        lifetimeTokens: Int64?, peakDailyTokens: Int64?, currentStreakDays: Int64?,
        longestStreakDays: Int64?, longestRunningTurnSec: Int64?
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.longestRunningTurnSec = longestRunningTurnSec
    }
}
