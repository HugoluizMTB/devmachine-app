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

    static func width(for harnessCount: Int, metrics m: DMMetrics = DMMetrics(scale: 1)) -> CGFloat {
        let columns = CGFloat(columnCount(for: harnessCount))
        return columns * m.pt(cardWidth) + (columns - 1) * m.pt(spacing)
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
        /// The clock sits in the middle of all of Home, not of the column
        /// beside the cards, when it still clears the cards by the gap there.
        var clockCentredInHome = false
        /// The machine cards open the page, top left, with usage under them.
        var cardsEdge: HorizontalEdge { .leading }
    }

    static func twoMachineCardsWidth(_ m: DMMetrics) -> CGFloat {
        m.pt(MachineStatsCard.width) * 2 + m.pt(cardSpacing)
    }

    static func plan(width: CGFloat, harnessCount: Int, metrics m: DMMetrics = DMMetrics(scale: 1)) -> Plan {
        let inner = max(0, width - m.pt(padding) * 2)
        let oneColumn = min(harnessCount, 1)
        let cardsWidth: (Int) -> CGFloat = { columns in
            max(columns > 0 ? HomeUsageLayout.width(for: columns, metrics: m) : 0, twoMachineCardsWidth(m))
        }
        var columns = oneColumn
        if harnessCount >= 2, inner - cardsWidth(2) - m.pt(gap) >= m.pt(roomyClockWidth) {
            columns = 2
        }
        let cards = cardsWidth(columns)
        let clockWidth = inner - cards - m.pt(gap)
        if clockWidth < m.pt(minClockWidth) {
            return Plan(stacked: true, usageColumns: oneColumn, cardsWidth: cards, clockSize: clockSize(for: inner))
        }
        let size = clockSize(for: clockWidth)
        let centred = HomeClockPlacement.centresInHome(
            homeWidth: width, cardsMaxX: m.pt(padding) + cards,
            clockWidth: m.pt(size) * clockWidthPerPoint, gap: m.pt(gap))
        return Plan(
            stacked: false, usageColumns: columns, cardsWidth: cards, clockSize: size, clockCentredInHome: centred)
    }

    private static func clockSize(for width: CGFloat) -> CGFloat {
        min(maxClockSize, max(minClockSize, (width / clockWidthPerPoint).rounded(.down)))
    }
}

/// Where Home's parts were laid out, for the network map wallpaper's free area.
private struct HomeFrames: Equatable {
    var size: CGSize = .zero
    /// Home's own frame in the window, to place the sidebar button in Home's coordinates.
    var inWindow: CGRect = .zero
    var clock: CGRect?
    var pill: CGRect?
    var stackedContent: CGRect?
}

struct HomeView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var usage: HarnessUsageStore
    @EnvironmentObject var stats: StatsStore
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade
    @Environment(\.collapsedSidebarButtonFrame) private var sidebarButton
    @ObservedObject private var readiness = MachineReadinessStore.shared
    @State private var frames = HomeFrames()

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
            let plan = HomeLayout.plan(width: proxy.size.width, harnessCount: usage.states.count, metrics: m)
            VStack(spacing: m.space.xl) {
                if plan.stacked {
                    stackedLayout(plan)
                } else {
                    sideBySideLayout(plan)
                }
                HStack {
                    Spacer()
                    compactStatCluster
                        .fixedSize()
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                            frames.pill = $0
                        }
                }
            }
            .padding(m.pt(HomeLayout.padding))
            .onAppear { frames.size = proxy.size }
            .onChange(of: proxy.size) { _, size in frames.size = size }
            .onGeometryChange(for: CGRect.self) { _ in proxy.frame(in: .named(ContentView.windowSpace)) } action: {
                frames.inWindow = $0
            }
        }
        .coordinateSpace(.named(Self.space))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WallpaperBackground(mapPlacement: mapPlacement))
        .clipped()
        .onAppear {
            usage.beginObserving()
            usage.refresh()
            stats.start()
        }
        .onDisappear { usage.endObserving() }
    }

    private static let space = "home"

    /// Pushes the cards (and, stacked, everything) down so the floating
    /// button that reopens the sidebar covers none of them.
    private var sidebarButtonInset: CGFloat {
        let button = sidebarButton?.offsetBy(dx: -frames.inWindow.minX, dy: -frames.inWindow.minY)
        let padding = m.pt(HomeLayout.padding)
        return FloatingButtonClearance.topInset(
            button: button, contentMinX: padding, contentMinY: padding, gap: m.space.md)
    }

    /// The large map is centred in all of Home and clears the stats pill;
    /// the compact one keeps to Home's free area.
    private func mapPlacement(_ size: NetworkMapSize) -> NetworkMapPlacement {
        switch size {
        case .large:
            guard frames.size.width > 0 else { return .none }
            return .filling(HomeMapArea.large(
                size: frames.size, padding: m.pt(HomeLayout.padding), gap: m.pt(HomeLayout.gap),
                pillMinY: frames.pill.map { Double($0.minY) }))
        case .compact:
            return compactMapPlacement
        }
    }

    /// Home's free area for the compact network map, from the plan and
    /// where the clock, the stacked content and the pill were laid out.
    private var compactMapPlacement: NetworkMapPlacement {
        guard let pill = frames.pill, frames.size.width > 0 else { return .none }
        let plan = HomeLayout.plan(width: frames.size.width, harnessCount: usage.states.count, metrics: m)
        let padding = m.pt(HomeLayout.padding), gap = m.pt(HomeLayout.gap)
        let layout: HomeMapArea.Layout
        if plan.stacked {
            guard let content = frames.stackedContent else { return .none }
            layout = .stacked(contentMaxY: content.maxY)
        } else {
            guard let clock = frames.clock else { return .none }
            layout = .sideBySide(cardsMaxX: padding + plan.cardsWidth, clockMaxY: clock.maxY)
        }
        let area = HomeMapArea.rect(size: frames.size, padding: padding, gap: gap, pillMinY: pill.minY, layout: layout)
        return area.map(NetworkMapPlacement.area) ?? .none
    }

    private func sideBySideLayout(_ plan: HomeLayout.Plan) -> some View {
        HStack(alignment: .top, spacing: m.pt(HomeLayout.gap)) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: m.pt(14)) {
                    machinesSection
                    usageGrid(columns: plan.usageColumns)
                }
                .padding(.top, sidebarButtonInset)
                .frame(width: plan.cardsWidth, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(width: plan.cardsWidth)
            if plan.clockCentredInHome {
                Spacer(minLength: 0)
            } else {
                clock(size: plan.clockSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            // Across the whole row, so its middle is Home's; the row has the
            // column's height, so the clock stays at the same height.
            if plan.clockCentredInHome {
                clock(size: plan.clockSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }

    private func stackedLayout(_ plan: HomeLayout.Plan) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: m.pt(20)) {
                machinesSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                clock(size: plan.clockSize)
                    .padding(.vertical, m.space.lg)
                usageGrid(columns: plan.usageColumns)
            }
            .padding(.top, sidebarButtonInset)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                frames.stackedContent = $0
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func clock(size: CGFloat) -> some View {
        TimelineView(.everyMinute) { ctx in
            VStack(spacing: m.space.sm) {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.dm(size, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(radius: m.pt(18), y: m.pt(2))
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.dm(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(verbatim: Self.macName())
                    .font(.dm(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                frames.clock = $0
            }
        }
    }

    @ViewBuilder
    private func usageGrid(columns: Int) -> some View {
        if columns > 0 {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(m.pt(HomeUsageLayout.cardWidth)), spacing: m.pt(HomeUsageLayout.spacing), alignment: .top),
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
        .harnessUsageErrorView { error, retry in
            DMErrorStateView(state: DMErrorState(error), retry: retry)
                .padding(.vertical, m.space.md)
        }
        .frame(width: m.pt(HomeUsageLayout.cardWidth))
        .clipShape(RoundedRectangle(cornerRadius: m.radius.card))
        .dmGlass(radius: DMRadius.card, stroke: .white.opacity(0.15))
    }

    private var machinesSection: some View {
        VStack(alignment: .leading, spacing: m.pt(14)) {
            ForEach(readiness.machinesNeedingAttention, id: \.self) { machine in
                MachineReadinessCard(store: readiness, machine: machine)
                    .dmGlass(radius: DMRadius.panel, stroke: .white.opacity(0.15))
            }
            machineCards
        }
    }

    @ViewBuilder
    private var machineCards: some View {
        if !stats.machines.isEmpty {
            VStack(alignment: .leading, spacing: m.space.md) {
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
        HStack(spacing: m.space.sm) {
            Text(verbatim: "\(totalSessions) sessions")
            Text(verbatim: "·")
            Text(verbatim: "\(harnessSessions) with coding harnesses")
            Text(verbatim: "·")
            Text(verbatim: "\(workspaceCount) workspaces")
        }
        .font(.dm(11, weight: .medium))
        .foregroundStyle(.white.opacity(0.65))
        .padding(.vertical, m.space.md)
        .padding(.horizontal, m.space.lg)
        .dmGlass(radius: DMRadius.pill)
    }

}
