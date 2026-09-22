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

    public init(provider: any UsageProvider = DefaultUsageProvider()) {
        self.provider = provider
    }

    public func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot {
        let text = try provider.fetchUsageText()
        let plan = UsageParser.planName(fromClaudeJSON: provider.readClaudeJSON() ?? "")
        return HarnessUsageSnapshot(
            planName: plan,
            blocks: UsageParser.parseUsage(text),
            stats: provider.computeStats())
    }
}
