import Foundation

public struct CodexUsageProvider: HarnessUsageProvider {
    public let harnessID = "codex"
    private let transport: any CodexRPCTransport
    private let now: @Sendable () -> Date

    public init(
        transport: any CodexRPCTransport,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.now = now
    }

    public func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot {
        let account = try transport.accountSnapshot()
        let limits = orderedLimits(account.rateLimits)
        let blocks = limits.flatMap { snapshot -> [UsageBlock] in
            let name = snapshot.limitName ?? snapshot.limitId ?? "Usage"
            return [
                block(window: snapshot.primary, name: name, kind: .session),
                block(window: snapshot.secondary, name: name, kind: .weeklyAll)
            ].compactMap { $0 }
        }
        let buckets = (account.usage.dailyUsageBuckets ?? []).sorted { $0.startDate < $1.startDate }
        let today = Self.dayFormatter.string(from: now())
        let stats = buckets.isEmpty ? nil : UsageStats(
            dailyTotals: buckets.map { DayTokens(date: $0.startDate, tokens: $0.tokens) },
            modelTotals: [],
            todayTokens: buckets.first(where: { $0.startDate == today })?.tokens ?? 0,
            mostUsedModel: nil)

        return HarnessUsageSnapshot(
            planName: limits.compactMap(\.planType).first.map(Self.planName),
            blocks: blocks,
            stats: stats,
            summaryMetrics: summaryMetrics(account.usage.summary))
    }

    private func orderedLimits(_ response: CodexRateLimitsResponse) -> [CodexRateLimitSnapshot] {
        guard let values = response.rateLimitsByLimitId, !values.isEmpty else {
            return [response.rateLimits]
        }
        return values.keys.sorted().compactMap { values[$0] }
    }

    private func block(
        window: CodexRateLimitWindow?, name: String, kind: UsageBlockKind
    ) -> UsageBlock? {
        guard let window else { return nil }
        let duration = window.windowDurationMins.map(Self.duration) ?? "Window"
        let resets = window.resetsAt.map(Self.resetText) ?? ""
        let label = "\(name) · \(duration)"
        return UsageBlock(
            id: Self.stableID("\(name)|\(duration)|\(kind)"), kind: kind,
            label: label, percent: window.usedPercent, resets: resets)
    }

    private func summaryMetrics(_ summary: CodexUsageSummary) -> [UsageSummaryMetric] {
        var rows: [UsageSummaryMetric] = []
        if let value = summary.lifetimeTokens {
            rows.append(.init(id: "lifetimeTokens", label: "Lifetime tokens", value: UsageFormat.tokens(value)))
        }
        if let value = summary.peakDailyTokens {
            rows.append(.init(id: "peakDailyTokens", label: "Peak daily tokens", value: UsageFormat.tokens(value)))
        }
        if let value = summary.currentStreakDays {
            rows.append(.init(id: "currentStreakDays", label: "Current streak", value: "\(value) days"))
        }
        if let value = summary.longestStreakDays {
            rows.append(.init(id: "longestStreakDays", label: "Longest streak", value: "\(value) days"))
        }
        if let value = summary.longestRunningTurnSec {
            rows.append(.init(id: "longestRunningTurnSec", label: "Longest turn", value: "\(value) sec"))
        }
        return rows
    }

    private static func duration(_ minutes: Int64) -> String {
        if minutes % 10_080 == 0 { return "\(minutes / 10_080)w" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private static func resetText(_ timestamp: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func stableID(_ value: String) -> UUID {
        var high: UInt64 = 0xcbf29ce484222325
        var low: UInt64 = 0x84222325cbf29ce4
        for byte in value.utf8 {
            high = (high ^ UInt64(byte)) &* 0x100000001b3
            low = (low ^ UInt64(byte)) &* 0x100000001b3
        }
        let text = String(format: "%08x-%04x-%04x-%04x-%012llx",
                          UInt32(truncatingIfNeeded: high >> 32),
                          UInt16(truncatingIfNeeded: high >> 16),
                          UInt16(truncatingIfNeeded: high),
                          UInt16(truncatingIfNeeded: low >> 48),
                          low & 0x0000ffffffffffff)
        return UUID(uuidString: text)!
    }

    private static func planName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
