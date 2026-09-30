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

/// Where Home puts the clock, the machine cards and the usage cards for a
/// given width, so none of them ever draws over another.
enum HomeLayout {
    static let padding: CGFloat = 24
    static let gap: CGFloat = 24
    static let cardSpacing: CGFloat = 12
    static let maxClockSize: CGFloat = 150
    static let minClockSize: CGFloat = 64
    /// "00:00" in the thin rounded face is about 2.8 times its point size wide.
    static let clockWidthPerPoint: CGFloat = 2.8
    static let minClockWidth: CGFloat = 300
    static let roomyClockWidth: CGFloat = 520

    struct Plan: Equatable {
        let stacked: Bool
        let usageColumns: Int
        let cardsWidth: CGFloat
        let clockSize: CGFloat
        /// The machine cards open the page, top left, with usage under them.
        var cardsEdge: HorizontalEdge { .leading }
    }

    static var twoMachineCardsWidth: CGFloat { MachineStatsCard.width * 2 + cardSpacing }

    static func plan(width: CGFloat, harnessCount: Int) -> Plan {
        let inner = max(0, width - padding * 2)
        let oneColumn = min(harnessCount, 1)
        let cardsWidth: (Int) -> CGFloat = { columns in
            max(columns > 0 ? HomeUsageLayout.width(for: columns) : 0, twoMachineCardsWidth)
        }
        var columns = oneColumn
        if harnessCount >= 2, inner - cardsWidth(2) - gap >= roomyClockWidth {
            columns = 2
        }
        let cards = cardsWidth(columns)
        let clockWidth = inner - cards - gap
        if clockWidth < minClockWidth {
            return Plan(stacked: true, usageColumns: oneColumn, cardsWidth: cards, clockSize: clockSize(for: inner))
        }
        return Plan(stacked: false, usageColumns: columns, cardsWidth: cards, clockSize: clockSize(for: clockWidth))
    }

    private static func clockSize(for width: CGFloat) -> CGFloat {
        min(maxClockSize, max(minClockSize, (width / clockWidthPerPoint).rounded(.down)))
    }
}

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var usage: HarnessUsageStore
    @EnvironmentObject var stats: StatsStore
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade

    private var totalSessions: Int {
        model.sessionCount
    }
    private var harnessSessions: Int {
        model.harnessSessionCount
    }
    private var workspaceCount: Int { model.visibleWorkspaces.count }

    static func macName(demo: Bool = DemoMode.isActive) -> String {
        demo ? DemoData.macName : (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }

    var body: some View {
        GeometryReader { proxy in
            let plan = HomeLayout.plan(width: proxy.size.width, harnessCount: usage.states.count)
            VStack(spacing: 16) {
                if plan.stacked {
                    stackedLayout(plan)
                } else {
                    sideBySideLayout(plan)
                }
                HStack {
                    Spacer()
                    compactStatCluster
                        .fixedSize()
                }
            }
            .padding(HomeLayout.padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WallpaperBackground())
        .clipped()
        .onAppear {
            usage.beginObserving()
            usage.refresh()
            stats.start()
        }
        .onDisappear { usage.endObserving() }
    }

    private func sideBySideLayout(_ plan: HomeLayout.Plan) -> some View {
        HStack(alignment: .top, spacing: HomeLayout.gap) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    machinesSection
                    usageGrid(columns: plan.usageColumns)
                }
                .frame(width: plan.cardsWidth, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(width: plan.cardsWidth)
            clock(size: plan.clockSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stackedLayout(_ plan: HomeLayout.Plan) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 20) {
                machinesSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                clock(size: plan.clockSize)
                    .padding(.vertical, 12)
                usageGrid(columns: plan.usageColumns)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func clock(size: CGFloat) -> some View {
        TimelineView(.everyMinute) { ctx in
            VStack(spacing: 6) {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.dm(size, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(radius: 18, y: 2)
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.dm(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(verbatim: Self.macName())
                    .font(.dm(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func usageGrid(columns: Int) -> some View {
        if columns > 0 {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(HomeUsageLayout.cardWidth), spacing: HomeUsageLayout.spacing, alignment: .top),
                    count: columns),
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(usage.states) { state in
                    if let descriptor = harnessSettingsFacade.descriptor(
                        for: HarnessID(rawValue: state.harnessID)) {
                        usageCard(state: state, descriptor: descriptor)
                    }
                }
            }
        }
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

    @ViewBuilder
    private var machinesSection: some View {
        if !stats.machines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("MACHINES")
                    .font(.dm(11, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.4), radius: 4)
                FlowLayout(spacing: HomeLayout.cardSpacing, rowSpacing: HomeLayout.cardSpacing) {
                    ForEach(stats.machines) { machine in
                        MachineStatsCard(
                            machine: machine,
                            state: stats.state(for: machine.name),
                            containerCount: { model.visibleContainers(in: $0).count },
                            action: { openStats(for: machine.name) })
                    }
                }
            }
        }
    }

    private func openStats(for machine: String) {
        stats.select(machine)
        model.showPage(.stats)
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
