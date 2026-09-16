import SwiftUI
import AppKit
import DevmachineCore

enum ContextTab: String, CaseIterable {
    case context
    case files
    case git

    var title: String {
        switch self {
        case .context: return "Context"
        case .files: return "Files"
        case .git: return "Git"
        }
    }
}

struct ContextPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: ContextStore
    @StateObject private var gitStore = GitStore()
    @StateObject private var fileTreeStore = FileTreeStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBody
        }
        .background(Color.dmSidebarBg)
    }

    private var session: (alias: String, name: String)? {
        guard case let .session(alias, name) = model.selection else { return nil }
        return (alias, name)
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.contextTab {
        case .context:
            contextBody
        case .files:
            if let session {
                FilesTab(store: fileTreeStore, alias: session.alias, session: session.name)
            } else {
                message("No session")
            }
        case .git:
            if let session {
                GitTab(store: gitStore, alias: session.alias, session: session.name)
            } else {
                message("No session")
            }
        }
    }

    @ViewBuilder
    private var contextBody: some View {
        if let session {
            ShortcutsSection(alias: session.alias, session: session.name)
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
        } else {
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
            showBottomDivider: true,
            label: {
                DMTabStrip(
                    tabs: ContextTab.allCases,
                    selection: $model.contextTab,
                    title: { $0.title },
                    fontSize: 11,
                    horizontalPadding: 8,
                    verticalPadding: 3,
                    cornerRadius: 6,
                    spacing: 2
                )
            },
            trailing: {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { model.contextCollapsed = true }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.dm(13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dmMuted)
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
            showBottomDivider: true,
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
            .padding(.vertical, 5)
    }

    private func agentRow(_ agent: ContextState.Agent) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(agent.label)
                .font(.dm(12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.vertical, 5)
    }

    private func todoSection(_ plan: ContextState.Plan?) -> some View {
        DMSection(
            contentSpacing: 9,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            showBottomDivider: true,
            label: { sectionLabel("TODO") },
            trailing: { sectionTrailing(plan.map { "\($0.done)/\($0.total)" } ?? "0") }
        ) {
            if let plan {
                DMProgressBar(done: plan.done, total: plan.total)
                VStack(alignment: .leading, spacing: 3) {
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
        return HStack(alignment: .top, spacing: 8) {
            Text(symbol)
                .font(.dm(10))
                .foregroundStyle(color)
                .frame(width: 12, alignment: .leading)
                .padding(.top, 1)
            Text(item.text)
                .font(.dm(12))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func prsSection(_ prs: [ContextState.PR]) -> some View {
        DMSection(
            contentSpacing: 7,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            showBottomDivider: true,
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pr.rowState.glyph)
                .font(.dm(11, weight: .semibold))
                .foregroundStyle(pr.rowState.color)
                .frame(width: 14)
                .help(pr.rowState.label)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
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
            Spacer(minLength: 4)
            threadsMark(pr.threads)
            ciMark(pr.ciState)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) }
        }
    }

    @ViewBuilder
    private func ciMark(_ ci: CIState) -> some View {
        if ci != .none {
            Image(systemName: ci.glyph)
                .font(.dm(10, weight: .semibold))
                .foregroundStyle(ci.color)
                .frame(width: 18, height: 18)
                .background(ci.color.opacity(0.12))
                .clipShape(Circle())
                .help(ci.help)
        }
    }

    @ViewBuilder
    private func threadsMark(_ threads: Int?) -> some View {
        if let count = threads, count > 0 {
            HStack(spacing: 2) {
                Image(systemName: "bubble.left.fill").font(.dm(9))
                Text(verbatim: "\(count)").font(.dm(10, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0xE0B341))
            .help(count == 1 ? "1 review comment to answer" : "\(count) review comments to answer")
            .padding(.top, 2)
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
        HStack(spacing: 8) {
            if link.kind == "linear" {
                DMPill(
                    text: "LINEAR",
                    color: Color(hex: 0xB07FD0),
                    font: .dm(9, weight: .semibold),
                    backgroundOpacity: 0.18
                )
            }
            Text(link.label)
                .font(.dm(12))
                .foregroundStyle(Color(hex: 0x5AA9E6))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            if let u = URL(string: link.url) { NSWorkspace.shared.open(u) }
        }
    }
}

struct ContextCollapsedStrip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { model.contextCollapsed = false }
        } label: {
            VStack(spacing: 18) {
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
                    .frame(width: 14, height: 78)

                Spacer()
            }
            .padding(.top, 12)
            .frame(width: 34)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open context")
        .background(Color.dmSidebarBg)
    }
}
