import SwiftUI
import AppKit
import DevmachineCore

/// What a background row is doing, from the word the engine reports.
enum RunningStatus: Equatable {
    case running, done, failed

    init(_ raw: String) {
        switch raw.lowercased() {
        case "done", "completed", "finished": self = .done
        case "failed", "error", "killed": self = .failed
        default: self = .running
        }
    }
}

enum ContextTab: String, CaseIterable {
    case context
    case preview
    case files
    case git

    var title: String {
        switch self {
        case .context: return "Context"
        case .preview: return "Preview"
        case .files: return "Files"
        case .git: return "Git"
        }
    }
}

struct ContextPanel: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: ContextStore
    @StateObject private var gitStore = GitStore()
    @StateObject private var quickPublish = QuickPublishState()
    @EnvironmentObject private var fileTreeStore: FileTreeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var stats: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBody
        }
        .task(id: workspaceName) {
            if let workspaceName {
                await WorkspaceMachineData.shared.warm(workspace: workspaceName, stats: stats)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.showsSkeleton)
        .background(Color.dmSidebarBg)
        .quickPublishSheet(quickPublish, settings: settingsStore.settings, workspaces: model.visibleWorkspaces)
    }

    private var session: (alias: String, name: String)? {
        guard case let .session(alias, name) = model.selection else { return nil }
        return (alias, name)
    }

    private var workspaceName: String? {
        guard let alias = session?.alias else { return nil }
        return model.visibleWorkspaces.first(where: { $0.alias == alias })?.name
    }

    /// Where the Files and Git tabs read from: the host for a remote session,
    /// this Mac for a local one.
    private var commandTarget: CommandTarget? {
        model.selectedSessionTarget
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.contextTab {
        case .context:
            contextBody
        case .preview:
            if let place = model.selectedPreviewPlace {
                PreviewSidebarTab(place: place)
            } else {
                message("No session")
            }
        case .files:
            if let commandTarget {
                FilesTab(store: fileTreeStore, target: commandTarget)
            } else {
                message("No session")
            }
        case .git:
            if let commandTarget {
                GitTab(store: gitStore, target: commandTarget, workspace: workspaceName)
            } else {
                message("No session")
            }
        }
    }

    @ViewBuilder
    private var contextBody: some View {
        if let commandTarget {
            ShortcutsSection(target: commandTarget)
        }
        if let alias = session?.alias, model.hasCaddyMachine, let workspaceName = model.visibleWorkspaces.first(where: { $0.alias == alias })?.name {
            publishRow(workspaceName)
        }
        if let state = store.state {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    runningSection("MONITORS", state.monitors)
                    runningSection("SHELLS", state.shells)
                    runningSection("SUB-AGENTS", state.agents)
                    todoSection(state.plan)
                    if !state.prs.isEmpty {
                        prsSection(state.prs)
                    }
                    if !state.links.isEmpty {
                        linksSection(state.links)
                    }
                }
            }
            // An overlay, not a row above the list: a failed poll every 5s on a
            // flaky link would otherwise push the whole list down and back.
            .overlay(alignment: .bottom) { staleBanner }
            .overlay(alignment: .topTrailing) {
                DMAgeLabel(since: store.stateReadAt, staleAfter: 30)
                    .padding(.horizontal, m.pt(14))
                    .padding(.top, m.space.sm)
            }
            .transition(.opacity)
        } else {
            contextStatus
        }
    }

    private func publishRow(_ workspaceName: String) -> some View {
        DMButton("Publish a port…", systemImage: "globe", variant: .outline, size: .small) {
            quickPublish.start(workspace: workspaceName, stats: stats)
        }
        .padding(.horizontal, m.pt(14))
        .padding(.top, m.space.md)
    }

    @ViewBuilder
    private var staleBanner: some View {
        if case .failed(let reason) = store.status {
            DMBanner(message: "Couldn't refresh: \(reason)", lineLimit: 2) {
                DMIconButton(systemImage: "arrow.clockwise", size: DMMetrics.baseFontSize, tint: nil) { store.retry() }
                    .help("Try again")
            }
            .background(Color.dmSidebarBg)
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

    private var header: some View {
        DMSection(
            headerSpacing: 6,
            padding: EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14),
            label: {
                DMTabStrip(
                    tabs: ContextTab.allCases,
                    selection: $model.contextTab,
                    title: { $0.title },
                    fontSize: 11,
                    horizontalPadding: 8,
                    verticalPadding: 3,
                    cornerRadius: DMRadius.row,
                    spacing: 2
                )
            },
            trailing: {
                if let session {
                    TerminalTransportBadge(kind: .remote(alias: session.alias, session: session.name))
                }
                DMIconButton(systemImage: "sidebar.right", size: 13, weight: .semibold) {
                    withAnimation(.easeInOut(duration: 0.18)) { model.contextCollapsed = true }
                }
                .help("Close context")
            }
        )
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
            trailing: { sectionTrailing("\(rows.count)") }
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
            label: { sectionLabel("TODO") },
            trailing: { sectionTrailing(plan.map { "\($0.done)/\($0.total)" } ?? "0") }
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
            trailing: { sectionTrailing("\(prs.count)") }
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
            trailing: { sectionTrailing("\(links.count)") }
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
        ScrollView {
            DMSkeleton {
                VStack(alignment: .leading, spacing: 0) {
                    section("MONITORS") { agentRows(1) }
                    section("SHELLS") { agentRows(2) }
                    section("SUB-AGENTS") { agentRows(1) }
                    section("TODO", spacing: 9) {
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
        .scrollDisabled(true)
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

struct ContextCollapsedStrip: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { model.contextCollapsed = false }
        } label: {
            VStack(spacing: m.pt(18)) {
                Image(systemName: "sidebar.right")
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)

                // rotationEffect keeps the pre-rotation layout size, so reserve
                // the rotated text's real footprint (narrow width, tall height)
                // to stop it overlapping the icon above it.
                Text("CONTEXT")
                    .font(.dm(10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: m.pt(14), height: m.pt(78))

                Spacer()
            }
            .padding(.top, m.space.lg)
            .frame(width: m.pt(34))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open context")
        .background(Color.dmSidebarBg)
    }
}
