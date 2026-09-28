import SwiftUI
import AppKit
import HarnessUsageKit
import DevmachineCore

enum HomeUsageLayout {
    static let cardWidth: CGFloat = UsagePanelMetrics.columnWidth
    static let spacing: CGFloat = 14

    static func columnCount(for harnessCount: Int) -> Int {
        min(max(harnessCount, 1), 2)
    }

    static func width(for harnessCount: Int) -> CGFloat {
        let columns = CGFloat(columnCount(for: harnessCount))
        return columns * cardWidth + (columns - 1) * spacing
    }
}

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var usage: HarnessUsageStore
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade

    private var totalSessions: Int {
        model.sessionCount
    }
    private var harnessSessions: Int {
        model.harnessSessionCount
    }
    private var workspaceCount: Int { model.visibleWorkspaces.count }

    private var systemName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                Spacer()

                TimelineView(.everyMinute) { ctx in
                    VStack(spacing: 6) {
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.dm(150, weight: .thin, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(radius: 18, y: 2)
                        Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.dm(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(systemName)
                            .font(.dm(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()
            }

            VStack {
                HStack(alignment: .top, spacing: 14) {
                    Spacer()
                    ScrollView(.vertical) {
                        LazyVGrid(columns: usageColumns, alignment: .trailing, spacing: 14) {
                            ForEach(usage.states) { state in
                                if let descriptor = harnessSettingsFacade.descriptor(
                                    for: HarnessID(rawValue: state.harnessID)) {
                                    usageCard(state: state, descriptor: descriptor)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: HomeUsageLayout.width(for: usage.states.count))
                }
                Spacer()
            }
            .padding(24)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    compactStatCluster
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WallpaperBackground())
        .clipped()
        .onAppear {
            usage.beginObserving()
            usage.refresh()
        }
        .onDisappear { usage.endObserving() }
    }

    private var usageColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(HomeUsageLayout.cardWidth),
                spacing: HomeUsageLayout.spacing,
                alignment: .top),
            count: HomeUsageLayout.columnCount(for: usage.states.count))
    }

    private func usageCard(
        state: HarnessUsageState, descriptor: HarnessDescriptor
    ) -> some View {
        HarnessUsageCardContent(
            state: state,
            title: "\(descriptor.shortTitle) Usage",
            systemImage: descriptor.systemImage,
            accent: descriptor.color,
            onRefresh: { usage.refresh(force: true) },
            scrollsContent: false)
        .frame(width: HomeUsageLayout.cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: DMRadius.card))
        .dmGlass(radius: DMRadius.card, stroke: .white.opacity(0.15))
    }

    private var compactStatCluster: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(totalSessions) sessions")
            Text(verbatim: "·")
            Text(verbatim: "\(harnessSessions) with coding harnesses")
            Text(verbatim: "·")
            Text(verbatim: "\(workspaceCount) workspaces")
        }
        .font(.dm(11, weight: .medium))
        .foregroundStyle(.white.opacity(0.65))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .dmGlass(radius: DMRadius.pill)
    }

}
