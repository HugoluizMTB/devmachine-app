import Foundation

public struct UsageSummaryMetric: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct HarnessUsageSnapshot: Equatable, Sendable {
    public let planName: String?
    public let blocks: [UsageBlock]
    public let stats: UsageStats?
    public let summaryMetrics: [UsageSummaryMetric]

    public init(
        planName: String? = nil,
        blocks: [UsageBlock] = [],
        stats: UsageStats? = nil,
        summaryMetrics: [UsageSummaryMetric] = []
    ) {
        self.planName = planName
        self.blocks = blocks
        self.stats = stats
        self.summaryMetrics = summaryMetrics
    }
}

public protocol HarnessUsageProvider: Sendable {
    var harnessID: String { get }
    func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot
}

public struct ClaudeUsageProvider: HarnessUsageProvider {
    public let harnessID = "claude"
    private let provider: any UsageProvider
    private let statsPollSeconds: TimeInterval
    private let now: @Sendable () -> Date
    private let cache = StatsCache()

    public init(
        provider: any UsageProvider = DefaultUsageProvider(),
        statsPollSeconds: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.statsPollSeconds = statsPollSeconds
        self.now = now
    }

    public func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot {
        let date = now()
        let stats = cache.value(at: date, maxAge: statsPollSeconds) ?? {
            let value = provider.computeStats()
            cache.store(value, at: date)
            return value
        }()
        let plan = UsageParser.planName(fromClaudeJSON: provider.readClaudeJSON() ?? "")
        do {
            let text = try provider.fetchUsageText()
            return HarnessUsageSnapshot(
                planName: plan, blocks: UsageParser.parseUsage(text), stats: stats)
        } catch {
            if let previous {
                return HarnessUsageSnapshot(
                    planName: plan ?? previous.planName,
                    blocks: previous.blocks,
                    stats: stats,
                    summaryMetrics: previous.summaryMetrics)
            }
            return HarnessUsageSnapshot(planName: plan, stats: stats)
        }
    }
}

private final class StatsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: (UsageStats, Date)?

    func value(at date: Date, maxAge: TimeInterval) -> UsageStats? {
        lock.withLock {
            guard let cached, date.timeIntervalSince(cached.1) < maxAge else { return nil }
            return cached.0
        }
    }

    func store(_ value: UsageStats, at date: Date) {
        lock.withLock { cached = (value, date) }
    }
}
