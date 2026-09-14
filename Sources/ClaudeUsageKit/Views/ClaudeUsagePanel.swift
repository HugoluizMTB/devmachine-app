import SwiftUI

public struct ClaudeUsagePanel: View {
    @ObservedObject var store: ClaudeUsageStore

    public init(store: ClaudeUsageStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                UsageHeaderView(
                    planName: store.planName,
                    refreshedAt: store.refreshedAt,
                    onRefresh: {
                        store.refresh(force: true)
                        store.refreshStats(force: true)
                    }
                )

                if let errorText = store.errorText {
                    VStack(spacing: 8) {
                        Text(verbatim: "Can't reach Claude")
                            .font(.headline)
                            .foregroundColor(UsagePalette.primaryText)
                        Text(verbatim: errorText)
                            .font(.caption)
                            .foregroundColor(UsagePalette.secondaryText)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            store.refresh(force: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if store.isLoading && store.blocks.isEmpty {
                    Text(verbatim: "Loading…")
                        .foregroundColor(UsagePalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    UsageBarsView(blocks: store.blocks)

                    Rectangle().fill(UsagePalette.divider).frame(height: 1)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: "Stats")
                            .font(.headline)
                            .foregroundColor(UsagePalette.primaryText)

                        Text(verbatim: "Today: \(UsageFormat.tokens(store.stats?.todayTokens ?? 0)) tokens")
                            .font(.caption)
                            .foregroundColor(UsagePalette.secondaryText)

                        UsageDailyChartView(daily: store.stats?.dailyTotals ?? [])

                        UsageModelBreakdownView(
                            models: store.stats?.modelTotals ?? [],
                            mostUsed: store.stats?.mostUsedModel
                        )
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .background(UsagePalette.background)
        .onAppear {
            store.refresh()
            store.refreshStats()
            store.beginObserving()
        }
        .onDisappear {
            store.endObserving()
        }
    }
}
