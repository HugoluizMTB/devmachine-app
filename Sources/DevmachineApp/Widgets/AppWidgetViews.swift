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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MachinesWidgetView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var stats: StatsStore
    @ObservedObject private var readiness = MachineReadinessStore.shared
    @Environment(\.dmMetrics) private var m

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: m.pt(14)) {
                ForEach(readiness.machinesNeedingAttention, id: \.self) { machine in
                    MachineReadinessCard(store: readiness, machine: machine)
                        .dmGlass(radius: DMRadius.panel, stroke: .white.opacity(0.15))
                }
                if !stats.machines.isEmpty {
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
                                action: { openStats(machine.name) })
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func openStats(_ machine: String) {
        stats.select(machine)
        model.showPage(.stats)
    }
}

struct HarnessUsageWidgetView: View {
    let harness: String
    @EnvironmentObject private var usage: HarnessUsageStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.harnessSettingsFacade) private var facade
    @Environment(\.dmMetrics) private var m

    var body: some View {
        let descriptor = facade.descriptor(for: HarnessID(rawValue: harness))
        if let descriptor, let state = usage.state(for: harness) {
            HarnessUsageCardContent(
                state: state,
                title: "\(descriptor.shortTitle) Usage",
                systemImage: descriptor.systemImage,
                accent: descriptor.color,
                onRefresh: { usage.refresh(harnessID: harness, force: true) },
                scrollsContent: true)
            .harnessUsageErrorView { error, retry in
                DMErrorStateView(state: DMErrorState(error), retry: retry)
                    .padding(.vertical, m.space.md)
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
            MachinesWidgetView()
        case "app.harness-usage":
            HarnessUsageWidgetView(harness: resolved.arguments["harness"] ?? "")
        default:
            WidgetPlaceholderView(
                icon: "questionmark.square.dashed", title: "Needs a newer app",
                detail: "This app cannot draw \(resolved.viewKind).")
        }
    }
}
