import SwiftUI
import AppKit

struct ContextPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: ContextStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if case let .session(alias, name) = model.selection {
                ShortcutsSection(alias: alias, session: name)
            }
            if let state = store.state {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !state.agents.isEmpty {
                            agentsSection(state.agents)
                        }
                        if let plan = state.plan {
                            planSection(plan)
                        }
                        if !state.prs.isEmpty {
                            prsSection(state.prs)
                        }
                        if !state.links.isEmpty {
                            linksSection(state.links)
                        }
                    }
                }
            } else {
                Spacer()
                Text("No context")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dmMuted)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .background(Color.dmSidebarBg)
    }

    private var header: some View {
        DMSection(
            headerSpacing: 6,
            padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
            showBottomDivider: true,
            label: {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("CONTEXT")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Color.dmMuted)
            },
            trailing: {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { model.contextCollapsed = true }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dmMuted)
                .help("Close context")
            }
        )
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Color.dmMuted)
    }

    @ViewBuilder
    private func sectionTrailing(_ trailing: String) -> some View {
        Text(trailing)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.dmMuted)
    }

    private func agentsSection(_ agents: [ContextState.Agent]) -> some View {
        DMSection(
            contentSpacing: 7,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            showBottomDivider: true,
            label: { sectionLabel("AGENTS") },
            trailing: { sectionTrailing("\(agents.count)") }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(agents.enumerated()), id: \.offset) { _, agent in
                    agentRow(agent)
                }
            }
        }
    }

    private func agentRow(_ agent: ContextState.Agent) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(agent.label)
                .font(.system(size: 12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.vertical, 5)
    }

    private func planSection(_ plan: ContextState.Plan) -> some View {
        DMSection(
            contentSpacing: 9,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            showBottomDivider: true,
            label: { sectionLabel("PLAN · \(plan.source)") },
            trailing: { sectionTrailing("\(plan.done)/\(plan.total)") }
        ) {
            DMProgressBar(done: plan.done, total: plan.total)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                    planItemRow(item)
                }
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
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 12, alignment: .leading)
                .padding(.top, 1)
            Text(item.text)
                .font(.system(size: 12))
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
                ForEach(prs, id: \.number) { pr in
                    prRow(pr)
                }
            }
        }
    }

    private func prRow(_ pr: ContextState.PR) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "#\(pr.number)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: 0x5AA9E6))
            Text(pr.repo)
                .font(.system(size: 12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
            Spacer()
            ciPill(pr.ci)
            reviewMark(pr.review)
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
    private func ciPill(_ ci: String) -> some View {
        switch ci {
        case "pass":
            DMPill(text: "CI", color: .green)
        case "fail":
            DMPill(text: "CI", color: .red)
        case "pending":
            DMPill(text: "CI", color: .yellow)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func reviewMark(_ review: String) -> some View {
        switch review {
        case "approved":
            Text("✓").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
        case "changes":
            Text("✗").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
        case "required":
            Text("!").font(.system(size: 12, weight: .semibold)).foregroundStyle(.yellow)
        default:
            EmptyView()
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
                    font: .system(size: 9, weight: .semibold),
                    backgroundOpacity: 0.18
                )
            }
            Text(link.label)
                .font(.system(size: 12))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)

                // rotationEffect keeps the pre-rotation layout size, so reserve
                // the rotated text's real footprint (narrow width, tall height)
                // to stop it overlapping the icon above it.
                Text("CONTEXT")
                    .font(.system(size: 10, weight: .bold))
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
