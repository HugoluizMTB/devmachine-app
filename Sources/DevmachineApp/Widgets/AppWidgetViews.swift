import SwiftUI
import AppKit
import DevmachineCore
import HarnessUsageKit

enum ClockWidgetSizing {
    static let maxSize: CGFloat = 150
    static let minSize: CGFloat = 24
    /// "00:00" in the thin rounded face is about 2.8 times its point size
    /// wide; the date and the Mac's name take the lower half.
    static let widthPerPoint: CGFloat = 2.8

    static func fontSize(width: CGFloat, height: CGFloat) -> CGFloat {
        min(maxSize, max(minSize, min(width / widthPerPoint, height * 0.5).rounded(.down)))
    }
}

struct ClockWidgetView: View {
    let size: CGSize
    @Environment(\.dmMetrics) private var m

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: m.space.sm) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.dm(
                        ClockWidgetSizing.fontSize(width: size.width / m.pt(1), height: size.height / m.pt(1)),
                        weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(radius: m.pt(18), y: m.pt(2))
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.dm(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(verbatim: HomeView.macName())
                    .font(.dm(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

struct SummaryWidgetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(spacing: m.space.sm) {
            Text(verbatim: "\(model.sessionCount) sessions")
            Text(verbatim: "·")
            Text(verbatim: "\(model.harnessSessionCount) with coding harnesses")
            Text(verbatim: "·")
            Text(verbatim: "\(model.visibleWorkspaces.count) workspaces")
        }
        .font(.dm(11, weight: .medium))
        .foregroundStyle(.white.opacity(0.65))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, m.space.md)
        .padding(.horizontal, m.space.lg)
        .dmGlass(radius: DMRadius.pill)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// "Which machines" is a list of names; none means all, so a machine added
/// later shows without a board edit. The store's order wins.
enum MachinesFilter {
    static func shown(_ machines: [StatsMachine], chosen: [String]) -> [StatsMachine] {
        chosen.isEmpty ? machines : machines.filter { chosen.contains($0.name) }
    }

    static func shown(names: [String], chosen: [String]) -> [String] {
        chosen.isEmpty ? names : names.filter(chosen.contains)
    }
}

/// A usage widget with no harness chosen shows the first enabled one.
enum UsageHarnessChoice {
    static func harness(_ argument: String, states: [HarnessUsageState]) -> String {
        argument.isEmpty ? states.first?.harnessID ?? "" : argument
    }
}

struct MachinesWidgetView: View {
    static let cardSpacing: CGFloat = 12
    /// A stats card with a snapshot at 100%; the tallest card drawn replaces it.
    static let nominalCardHeight: CGFloat = 132
    /// The opposite corner from the chrome's resize corner, so a press a
    /// little off that corner does not open Stats.
    static let moreChipAlignment: Alignment = .bottomLeading

    let size: CGSize
    var chosen: [String] = []
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var stats: StatsStore
    @ObservedObject private var readiness = MachineReadinessStore.shared
    @Environment(\.dmMetrics) private var m
    @State private var cardHeight: CGFloat?
    @State private var attentionHeight: CGFloat = 0

    private var machines: [StatsMachine] { MachinesFilter.shown(stats.machines, chosen: chosen) }

    var body: some View {
        let attention = MachinesFilter.shown(names: readiness.machinesNeedingAttention, chosen: chosen)
        let gridHeight = size.height - (attention.isEmpty ? 0 : attentionHeight + m.pt(Self.cardSpacing))
        let fit = CardGridFit.fit(
            in: CGSize(width: size.width, height: max(0, gridHeight)),
            card: CGSize(width: m.pt(MachineStatsCard.width), height: cardHeight ?? m.pt(Self.nominalCardHeight)),
            spacing: m.pt(Self.cardSpacing))
        VStack(alignment: .leading, spacing: m.pt(Self.cardSpacing)) {
            if !attention.isEmpty {
                VStack(alignment: .leading, spacing: m.pt(Self.cardSpacing)) {
                    ForEach(attention, id: \.self) { machine in
                        MachineReadinessCard(store: readiness, machine: machine)
                            .dmGlass(radius: DMRadius.panel, stroke: .white.opacity(0.15))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { attentionHeight = $0 }
            }
            grid(fit)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: Self.moreChipAlignment) { moreChip(fit.hidden(of: machines.count)) }
    }

    private func grid(_ fit: CardGridFit) -> some View {
        let shown = Array(machines.prefix(fit.shown(of: machines.count)))
        let columns = max(1, fit.columns)
        let rows = stride(from: 0, to: shown.count, by: columns).map { Array(shown[$0..<min($0 + columns, shown.count)]) }
        let spacing = m.pt(Self.cardSpacing) * fit.scale
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row) { machine in card(machine, scale: fit.scale) }
                }
            }
        }
    }

    private func card(_ machine: StatsMachine, scale: Double) -> some View {
        let height = cardHeight ?? m.pt(Self.nominalCardHeight)
        return MachineStatsCard(
            machine: machine,
            state: stats.state(for: machine.name),
            containerCount: { model.visibleContainers(in: $0).count },
            action: { openStats(machine.name) })
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
            if measured > (cardHeight ?? 0) { cardHeight = measured }
        }
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: m.pt(MachineStatsCard.width) * scale, height: height * scale, alignment: .topLeading)
    }

    @ViewBuilder
    private func moreChip(_ hidden: Int) -> some View {
        if hidden > 0 {
            DMButton("+\(hidden) more", variant: .ghost, size: .small) { model.showPage(.stats) }
                .dmGlass(radius: DMRadius.pill)
                .help(Text(verbatim: "Open Stats to see every machine"))
        }
    }

    private func openStats(_ machine: String) {
        stats.select(machine)
        model.showPage(.stats)
    }
}

/// Below this height (in points at 100%) a usage widget shows one line per
/// window; the full card with its charts needs about four rows of the grid.
enum UsageWidgetLayout {
    static let fullCardMinHeight: CGFloat = 240
    /// A small widget has room for the name, bar and percent, not the reset time.
    static let resetTimeMinWidth: CGFloat = 240

    static func showsFullCard(boardHeight: CGFloat) -> Bool {
        boardHeight >= fullCardMinHeight
    }

    static func showsResetTime(boardWidth: CGFloat) -> Bool {
        boardWidth >= resetTimeMinWidth
    }
}

struct HarnessUsageWidgetView: View {
    let argument: String
    let size: CGSize
    @EnvironmentObject private var usage: HarnessUsageStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.harnessSettingsFacade) private var facade
    @Environment(\.dmMetrics) private var m

    private var harness: String { UsageHarnessChoice.harness(argument, states: usage.states) }

    var body: some View {
        let descriptor = facade.descriptor(for: HarnessID(rawValue: harness))
        if let descriptor, let state = usage.state(for: harness) {
            Group {
                if UsageWidgetLayout.showsFullCard(boardHeight: size.height / m.pt(1)) {
                    HarnessUsageCardContent(
                        state: state,
                        title: "\(descriptor.shortTitle) Usage",
                        systemImage: descriptor.systemImage,
                        accent: descriptor.color,
                        onRefresh: refresh,
                        scrollsContent: true)
                    .harnessUsageErrorView { error, retry in
                        DMErrorStateView(state: DMErrorState(error), retry: retry)
                            .padding(.vertical, m.space.md)
                    }
                } else {
                    CompactUsageView(
                        state: state, title: "\(descriptor.shortTitle) Usage", systemImage: descriptor.systemImage,
                        accent: descriptor.color,
                        showsReset: UsageWidgetLayout.showsResetTime(boardWidth: size.width / m.pt(1)),
                        onRefresh: refresh)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: m.radius.card))
            .dmGlass(radius: DMRadius.card, stroke: .white.opacity(0.15))
        } else {
            WidgetPlaceholderView(
                icon: "gauge.with.dots.needle.33percent",
                title: "\(descriptor?.shortTitle ?? harness) is off",
                detail: "Turn it on in Settings → Harnesses to see its usage here.",
                actionTitle: "Open Settings",
                action: { model.openSettings(.harnesses) })
        }
    }

    private func refresh() {
        usage.refresh(harnessID: harness, force: true)
    }
}

/// One line per usage window: its name, a thin bar, the percent and when it
/// resets, in columns so the bars line up.
private struct CompactUsageView: View {
    let state: HarnessUsageState
    let title: String
    let systemImage: String
    let accent: Color
    let showsReset: Bool
    let onRefresh: () -> Void
    @Environment(\.dmMetrics) private var m

    var body: some View {
        let presentation = HarnessUsagePresentation(title: title, state: state)
        VStack(alignment: .leading, spacing: m.space.sm) {
            HStack(spacing: m.space.sm) {
                Label {
                    Text(verbatim: presentation.headerTitle)
                } icon: {
                    Image(systemName: systemImage)
                }
                .font(.dm(12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                Spacer(minLength: m.space.xs)
                DMIconButton(systemImage: "arrow.clockwise", action: onRefresh)
                    .help(Text(verbatim: "Refresh"))
            }
            if let error = presentation.error {
                DMErrorStateView(state: DMErrorState(error), retry: onRefresh)
            } else if state.showsSkeleton {
                ProgressView().controlSize(.small)
            } else if let snapshot = state.snapshot {
                Grid(alignment: .leading, horizontalSpacing: m.space.sm, verticalSpacing: m.space.md) {
                    ForEach(snapshot.blocks) { block in row(block) }
                }
            }
        }
        .padding(m.space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ block: UsageBlock) -> some View {
        GridRow {
            Text(verbatim: block.label)
                .font(.dm(11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            DMProgressBar(done: block.percent, total: 100, fillColor: accent, barHeight: 4, cornerRadius: 2)
                .frame(minWidth: m.pt(36))
                .gridColumnAlignment(.leading)
            Text(verbatim: "\(block.percent)%")
                .font(.dm(11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()
                .gridColumnAlignment(.trailing)
            if showsReset {
                Text(verbatim: block.resets)
                    .font(.dm(10))
                    .foregroundStyle(Color.dmMuted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

struct WidgetPlaceholderView: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            Label {
                Text(verbatim: title).font(.dm(12, weight: .semibold))
            } icon: {
                Image(systemName: icon)
            }
            Text(verbatim: detail)
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                DMButton(actionTitle, variant: .outline, size: .small, action: action)
            }
        }
        .padding(m.space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dmGlass(radius: DMRadius.card)
    }
}

struct AppWidgetView: View {
    let resolved: ResolvedWidget
    let size: CGSize

    var body: some View {
        switch resolved.viewKind {
        case "app.clock":
            ClockWidgetView(size: size)
        case "app.summary":
            SummaryWidgetView()
        case "app.machines":
            MachinesWidgetView(size: size, chosen: resolved.listArguments["machines"] ?? [])
        case "app.harness-usage":
            HarnessUsageWidgetView(argument: resolved.arguments["harness"] ?? "", size: size)
        case "app.pull-requests-panel":
            PRsView()
                .clipShape(RoundedRectangle(cornerRadius: DMRadius.card))
                .dmGlass(radius: DMRadius.card, stroke: .white.opacity(0.15))
        default:
            WidgetPlaceholderView(
                icon: "questionmark.square.dashed", title: "Needs a newer app",
                detail: "This app cannot draw \(resolved.viewKind).")
        }
    }
}
