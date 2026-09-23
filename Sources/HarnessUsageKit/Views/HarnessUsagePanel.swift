import SwiftUI

public enum UsagePanelMetrics {
    public static let columnWidth: CGFloat = 380
    public static let contentSpacing: CGFloat = 16
}

public struct HarnessUsagePresentation: Equatable, Sendable {
    public let title: String
    public let state: HarnessUsageState

    public init(title: String, state: HarnessUsageState) {
        self.title = title
        self.state = state
    }

    public var headerTitle: String {
        guard let plan = state.snapshot?.planName, !plan.isEmpty else { return title }
        return "\(title) (\(plan))"
    }

    public var errorTitle: String { "\(title) is unavailable" }
    public var errorText: String? { state.errorText }
    public var summaryMetrics: [UsageSummaryMetric] { state.snapshot?.summaryMetrics ?? [] }
    public var showsModelBreakdown: Bool { !(state.snapshot?.stats?.modelTotals.isEmpty ?? true) }
}

public struct HarnessUsagePanel: View {
    @ObservedObject private var store: HarnessUsageStore
    private let harnessID: String?
    private let title: String
    private let systemImage: String
    private let accent: Color

    public init(
        store: HarnessUsageStore,
        harnessID: String,
        title: String,
        systemImage: String,
        accent: Color
    ) {
        self.store = store
        self.harnessID = harnessID
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
    }

    /// Compatibility while app surfaces migrate to descriptor-driven inputs.
    public init(store: HarnessUsageStore) {
        self.store = store
        harnessID = nil
        title = "Usage"
        systemImage = "chart.bar.fill"
        accent = UsagePalette.accent
    }

    private var state: HarnessUsageState {
        if let harnessID, let state = store.state(for: harnessID) { return state }
        return store.states.first ?? HarnessUsageState(harnessID: harnessID ?? "usage")
    }

    public var body: some View {
        HarnessUsageCardContent(
            state: state,
            title: title,
            systemImage: systemImage,
            accent: accent,
            onRefresh: { store.refresh(force: true) })
        .onAppear {
            store.refresh()
            store.beginObserving()
        }
        .onDisappear { store.endObserving() }
    }
}

public struct HarnessUsageCardContent: View {
    public let state: HarnessUsageState
    public let title: String
    public let systemImage: String
    public let accent: Color
    public let onRefresh: () -> Void
    public let scrollsContent: Bool

    public init(
        state: HarnessUsageState,
        title: String,
        systemImage: String,
        accent: Color,
        onRefresh: @escaping () -> Void,
        scrollsContent: Bool = true
    ) {
        self.state = state
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.onRefresh = onRefresh
        self.scrollsContent = scrollsContent
    }

    public var body: some View {
        Group {
            if scrollsContent {
                ScrollView { content }
                    .scrollIndicators(.automatic)
            } else {
                content
            }
        }
        .background(UsagePalette.background)
    }

    private var presentation: HarnessUsagePresentation {
        HarnessUsagePresentation(title: title, state: state)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: UsagePanelMetrics.contentSpacing) {
            UsageHeaderView(
                title: presentation.headerTitle,
                systemImage: systemImage,
                refreshedAt: state.refreshedAt,
                onRefresh: onRefresh)

            if let errorText = presentation.errorText {
                VStack(spacing: 8) {
                    Text(verbatim: presentation.errorTitle)
                        .font(.headline)
                        .foregroundColor(UsagePalette.primaryText)
                    Text(verbatim: errorText)
                        .font(.caption)
                        .foregroundColor(UsagePalette.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Retry", action: onRefresh)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if state.isLoading && state.snapshot == nil {
                Text(verbatim: "Loading…")
                    .foregroundColor(UsagePalette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let snapshot = state.snapshot {
                if !snapshot.blocks.isEmpty {
                    UsageBarsView(blocks: snapshot.blocks, accent: accent)
                }
                if !snapshot.summaryMetrics.isEmpty {
                    UsageSummaryView(metrics: snapshot.summaryMetrics)
                }
                if let stats = snapshot.stats {
                    Rectangle().fill(UsagePalette.divider).frame(height: 1)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: "Stats")
                            .font(.headline)
                            .foregroundColor(UsagePalette.primaryText)
                        Text(verbatim: "Today: \(UsageFormat.tokens(stats.todayTokens)) tokens")
                            .font(.caption)
                            .foregroundColor(UsagePalette.secondaryText)
                        if !stats.dailyTotals.isEmpty {
                            UsageDailyChartView(daily: stats.dailyTotals, accent: accent)
                        }
                        if presentation.showsModelBreakdown {
                            UsageModelBreakdownView(
                                models: stats.modelTotals,
                                mostUsed: stats.mostUsedModel)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
