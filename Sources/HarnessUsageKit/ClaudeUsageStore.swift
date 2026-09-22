import SwiftUI

@MainActor
public final class ClaudeUsageStore: ObservableObject {
    @Published public var blocks: [UsageBlock] = []
    @Published public var stats: UsageStats?
    @Published public var planName: String = ""
    @Published public var errorText: String?
    @Published public var isLoading = false
    @Published public var refreshedAt: Date?

    private let provider: UsageProvider
    private let config: ClaudeUsageConfig
    private nonisolated(unsafe) var usageTimer: Timer?
    private nonisolated(unsafe) var statsTimer: Timer?
    private var observers = 0
    private var isFetchingUsage = false
    private var isComputingStats = false
    private var statsRefreshedAt: Date?

    public init(provider: UsageProvider = DefaultUsageProvider(), config: ClaudeUsageConfig = .init()) {
        self.provider = provider
        self.config = config
    }

    deinit {
        usageTimer?.invalidate()
        statsTimer?.invalidate()
    }

    public var isPolling: Bool { usageTimer != nil || statsTimer != nil }
    public var observerCount: Int { observers }

    // Each view that shows usage holds one observation; the timers run only
    // while at least one does. `fetchUsageText` spawns the Claude CLI, so
    // polling a closed popover is expensive, not just wasteful.
    public func beginObserving() {
        observers += 1
        guard observers == 1 else { return }
        startTimers()
    }

    public func endObserving() {
        guard observers > 0 else { return }
        observers -= 1
        guard observers == 0 else { return }
        stopTimers()
    }

    public func refresh(force: Bool = false) {
        guard force || isStale(refreshedAt, maxAge: config.usagePollSeconds) else { return }
        guard !isFetchingUsage else { return }
        isFetchingUsage = true
        isLoading = true
        errorText = nil
        let provider = self.provider

        Task.detached {
            do {
                let text = try provider.fetchUsageText()
                let parsedBlocks = UsageParser.parseUsage(text)
                let plan = UsageParser.planName(fromClaudeJSON: provider.readClaudeJSON() ?? "") ?? ""

                await MainActor.run {
                    self.blocks = parsedBlocks
                    self.planName = plan
                    self.refreshedAt = Date()
                    self.isLoading = false
                    self.isFetchingUsage = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = "\(error)"
                    self.isLoading = false
                    self.isFetchingUsage = false
                }
            }
        }
    }

    public func refreshStats(force: Bool = false) {
        guard force || isStale(statsRefreshedAt, maxAge: config.statsPollSeconds) else { return }
        guard !isComputingStats else { return }
        isComputingStats = true
        let provider = self.provider

        Task.detached {
            let computedStats = provider.computeStats()
            await MainActor.run {
                self.isComputingStats = false
                self.statsRefreshedAt = Date()
                if self.stats != computedStats {
                    self.stats = computedStats
                }
            }
        }
    }

    private func isStale(_ date: Date?, maxAge: TimeInterval) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) >= maxAge
    }

    private func startTimers() {
        usageTimer?.invalidate()
        statsTimer?.invalidate()

        usageTimer = Timer.scheduledTimer(withTimeInterval: config.usagePollSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh(force: true)
            }
        }
        statsTimer = Timer.scheduledTimer(withTimeInterval: config.statsPollSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshStats(force: true)
            }
        }
    }

    private func stopTimers() {
        usageTimer?.invalidate()
        statsTimer?.invalidate()
        usageTimer = nil
        statsTimer = nil
    }
}
