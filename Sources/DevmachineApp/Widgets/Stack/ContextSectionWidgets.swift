import SwiftUI
import AppKit
import DevmachineCore

/// Which section carries the status view and the age label: before the
/// first read, the board's first expanded one; after it, the first that
/// draws something, since empty pull requests or links draw nothing.
enum ContextSectionLead {
    static func draws(_ kind: StackAppViewKind, state: ContextState) -> Bool {
        switch kind {
        case .monitors, .shells, .subAgents, .todo: true
        case .pullRequests: !state.prs.isEmpty
        case .links: !state.links.isEmpty
        default: false
        }
    }

    static func isLead(_ kind: StackAppViewKind, preceding: [StackAppViewKind], state: ContextState?) -> Bool {
        guard let state else { return preceding.isEmpty }
        return draws(kind, state: state) && !preceding.contains { draws($0, state: state) }
    }
}

/// One context section as a stack widget. The sections are the panel's own
/// code; while nothing has been read, the board's first one (the lead)
/// shows the panel's status view and the others draw nothing.
struct ContextSectionWidgetView: View {
    let kind: StackAppViewKind
    @ObservedObject var store: ContextStore
    /// The expanded session-context sections above this one on the board.
    let preceding: [StackAppViewKind]
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @Environment(\.stackFillHeight) private var fillHeight

    private var isLead: Bool { ContextSectionLead.isLead(kind, preceding: preceding, state: store.state) }

    var body: some View {
        if let state = store.state, ContextSectionLead.draws(kind, state: state) {
            section(state)
                .overlay(alignment: .topTrailing) {
                    if isLead {
                        DMAgeLabel(since: store.stateReadAt, staleAfter: 30)
                            .padding(.horizontal, m.pt(14))
                            .padding(.top, m.space.sm)
                    }
                }
                .transition(.opacity)
        } else if store.state == nil, isLead {
            VStack(spacing: 0) { contextStatus }
                .frame(maxWidth: .infinity)
                .frame(height: max(fillHeight, m.pt(120)), alignment: .top)
                .clipped()
        } else {
            StackEmptyWidgetHeader()
        }
    }

    @ViewBuilder
    private func section(_ state: ContextState) -> some View {
        switch kind {
        case .monitors: runningSection("MONITORS", state.monitors)
        case .shells: runningSection("SHELLS", state.shells)
        case .subAgents: runningSection("SUB-AGENTS", state.agents).demoClickTarget("context:sub-agents")
        case .todo: todoSection(state.plan).demoClickTarget("context:todo")
        case .pullRequests: if !state.prs.isEmpty { prsSection(state.prs).demoClickTarget("context:pull-requests") }
        case .links: if !state.links.isEmpty { linksSection(state.links) }
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var contextStatus: some View {
        switch store.status {
        case .loading:
            ContextSkeleton()
                .transition(.opacity)
        case .failed(let reason):
            DMStatusView(kind: .failed(
                title: "Couldn't read the context", message: reason, retry: { store.retry() }))
        case .empty:
            DMStatusView(kind: .empty(
                systemImage: "text.bubble", text: "Nothing to show for this session yet"))
        case .idle, .loaded:
            message("No context")
        }
    }

    @ViewBuilder
    private func message(_ text: String) -> some View {
        Spacer()
        Text(text)
            .font(.dm(12))
            .foregroundStyle(Color.dmMuted)
            .frame(maxWidth: .infinity)
        Spacer()
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        DMSectionLabel(text: title)
    }

    @ViewBuilder
    private func sectionTrailing(_ trailing: String) -> some View {
        DMSectionValue(text: trailing)
    }

    private func runningSection(_ title: String, _ rows: [ContextState.Agent]) -> some View {
        DMSection(
            contentSpacing: 7,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            label: { sectionLabel(title) },
            trailing: {
                sectionTrailing("\(rows.count)")
                StackHeaderControls()
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    emptyRow
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        agentRow(row)
                    }
                }
            }
        }
    }

    private var emptyRow: some View {
        Text("empty")
            .font(.dm(12))
            .foregroundStyle(Color.dmMuted)
            .padding(.vertical, m.pt(5))
    }

    private func agentRow(_ agent: ContextState.Agent) -> some View {
        HStack(spacing: m.space.md) {
            // The spinner is for work still going. Everything spun before,
            // which made finished work look stuck for ever.
            switch RunningStatus(agent.status) {
            case .running:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.dm(11))
                    .foregroundStyle(.green)
                    .frame(width: m.pt(16))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.dm(11))
                    .foregroundStyle(.red)
                    .frame(width: m.pt(16))
            }
            Text(agent.label)
                .font(.dm(12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.vertical, m.pt(5))
    }

    private func todoSection(_ plan: ContextState.Plan?) -> some View {
        DMSection(
            contentSpacing: 9,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            label: { sectionLabel("TO-DO") },
            trailing: {
                sectionTrailing(plan.map { "\($0.done)/\($0.total)" } ?? "0")
                StackHeaderControls()
            }
        ) {
            if let plan {
                DMProgressBar(done: plan.done, total: plan.total)
                VStack(alignment: .leading, spacing: m.pt(3)) {
                    ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                        planItemRow(item)
                    }
                }
            } else {
                emptyRow
            }
        }
    }

    private func planItemRow(_ item: ContextState.Plan.Item) -> some View {
        let (symbol, color, textColor): (String, Color, Color) = {
            switch item.state {
            case "done": return ("✓", .green, Color.dmMuted)
            case "active": return ("●", .yellow, .white)
            default: return ("○", Color.dmDivider, Color.dmRowText)
            }
        }()
        return HStack(alignment: .top, spacing: m.space.md) {
            Text(symbol)
                .font(.dm(10))
                .foregroundStyle(color)
                .frame(width: m.pt(12), alignment: .leading)
                .padding(.top, 1)
            Text(item.text)
                .font(.dm(12))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, m.space.xxs)
    }

    private func prsSection(_ prs: [ContextState.PR]) -> some View {
        DMSection(
            contentSpacing: 7,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            label: { sectionLabel("PULL REQUESTS") },
            trailing: {
                sectionTrailing("\(prs.count)")
                StackHeaderControls()
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(prs) { pr in
                    prRow(pr)
                }
            }
        }
    }

    private func prRow(_ pr: ContextState.PR) -> some View {
        HStack(alignment: .top, spacing: m.space.md) {
            DMPRStateIcon(state: pr.rowState.kind, size: 12)
                .help(pr.rowState.help)
            VStack(alignment: .leading, spacing: m.space.xxs) {
                HStack(spacing: m.space.sm) {
                    Text(verbatim: "#\(pr.number)")
                        .font(.dm(12, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x5AA9E6))
                    Text(pr.repo)
                        .font(.dm(12))
                        .foregroundStyle(Color.dmRowText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !pr.title.isEmpty {
                    Text(pr.title)
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: m.space.xs)
            threadsMark(pr.threads)
            ciMark(pr.ciState)
        }
        .padding(.vertical, m.pt(5))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { openLink(pr.url) }
        .contextMenu { linkMenu(pr.url) }
    }

    @ViewBuilder
    private func ciMark(_ ci: CIState) -> some View {
        if ci != .none {
            Image(systemName: ci.glyph)
                .font(.dm(10, weight: .semibold))
                .foregroundStyle(ci.color)
                .frame(width: m.pt(18), height: m.pt(18))
                .background(ci.color.opacity(0.12))
                .clipShape(Circle())
                .help(ci.help)
        }
    }

    @ViewBuilder
    private func threadsMark(_ threads: Int?) -> some View {
        if let count = threads, count > 0 {
            HStack(spacing: m.space.xxs) {
                Image(systemName: "bubble.left.fill").font(.dm(9))
                Text(verbatim: "\(count)").font(.dm(10, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0xE0B341))
            .help(count == 1 ? "1 review comment to answer" : "\(count) review comments to answer")
            .padding(.top, m.space.xxs)
        }
    }

    private func linksSection(_ links: [ContextState.Link]) -> some View {
        DMSection(
            contentSpacing: 6,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            label: { sectionLabel("LINKS") },
            trailing: {
                sectionTrailing("\(links.count)")
                StackHeaderControls()
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(links, id: \.url) { link in
                    linkRow(link)
                }
            }
        }
    }

    private func linkRow(_ link: ContextState.Link) -> some View {
        HStack(spacing: m.space.md) {
            DMKindLabel(text: link.kind.uppercased())
            Text(link.label)
                .font(.dm(12))
                .foregroundStyle(Color(hex: 0x5AA9E6))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, m.space.xs)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { openLink(link.url) }
        .contextMenu { linkMenu(link.url) }
    }

    /// Follows "Open previews and links in"; ⌥-click takes the other place once.
    private func openLink(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        PreviewStore.shared.openLink(url, inverted: NSEvent.modifierFlags.contains(.option))
    }

    @ViewBuilder
    private func linkMenu(_ raw: String) -> some View {
        if let url = URL(string: raw) {
            let preference = model.settings?.linkOpening ?? .defaultBrowser
            Button("Open in Devmachine") { PreviewStore.shared.openLink(url, inverted: preference != .inApp) }
            Button("Open in Default Browser") { NSWorkspace.shared.open(url) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(raw, forType: .string)
            }
        }
    }
}

/// The context list before its first answer: the same sections, with
/// placeholder rows in the widths the panel has.
private struct ContextSkeleton: View {
    @Environment(\.dmMetrics) private var m
    var body: some View {
        DMSkeleton {
            VStack(alignment: .leading, spacing: 0) {
                section("MONITORS") { agentRows(1) }
                section("SHELLS") { agentRows(2) }
                section("SUB-AGENTS") { agentRows(1) }
                section("TO-DO", spacing: 9) {
                    DMSkeletonBlock(height: 5, radius: 3)
                    VStack(alignment: .leading, spacing: m.pt(3)) {
                        ForEach(0..<4, id: \.self) { index in
                            HStack(spacing: m.space.md) {
                                DMSkeletonBlock(width: .fixed(9), height: 9, radius: 4.5)
                                DMSkeletonText(size: 12, width: .varied(index))
                            }
                            .padding(.vertical, m.space.xxs)
                        }
                    }
                }
                section("PULL REQUESTS") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<2, id: \.self) { index in
                            prRow(index)
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String, spacing: CGFloat = 7,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DMSection(
            contentSpacing: spacing,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            label: { DMSectionLabel(text: title) },
            trailing: { DMSkeletonText(size: 10, weight: .bold, width: .fixed(10)) },
            content: content)
    }

    private func agentRows(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: m.space.md) {
                    DMSkeletonBlock(width: .fixed(14), height: 14, radius: 7)
                        .frame(width: m.pt(16))
                    DMSkeletonText(size: 12, width: .varied(index + count))
                }
                .padding(.vertical, m.pt(5))
            }
        }
    }

    private func prRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: m.space.md) {
            DMSkeletonBlock(width: .fixed(12), height: 12, radius: 6)
                .frame(width: m.pt(14))
                .padding(.top, m.space.xxs)
            VStack(alignment: .leading, spacing: m.space.xxs) {
                DMSkeletonText(size: 12, width: .varied(index, shares: [0.55, 0.42]))
                DMSkeletonText(size: 11, width: .varied(index, shares: [0.8, 0.66]))
            }
            DMSkeletonBlock(width: .fixed(18), height: 18, radius: 9)
        }
        .padding(.vertical, m.pt(5))
    }
}
