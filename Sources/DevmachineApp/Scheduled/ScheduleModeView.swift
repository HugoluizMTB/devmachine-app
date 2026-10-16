import SwiftUI
import DevmachineCore

/// Schedule mode: the scheduled tasks by workspace in the sidebar, the
/// Scheduled page beside it.
struct ScheduleModeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(spacing: 0) {
            if !model.sidebarCollapsed {
                ScheduleSidebar()
                    .modifier(SidebarUnderTitlebar())
                    .frame(width: m.pt(model.sidebarWidth))
                Color.dmSidebarBg.frame(width: m.pt(6))
            }
            ScheduledView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.dmContentBg.ignoresSafeArea())
        }
        .background(Color.dmSidebarBg)
    }
}

struct ScheduleSidebar: View {
    @ObservedObject private var store = ScheduledStore.shared
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    /// Workspaces in the order of their next task, as the page groups them.
    static func groups(_ rows: [ScheduledRow]) -> [(name: String, rows: [ScheduledRow])] {
        var order: [String] = []
        var byName: [String: [ScheduledRow]] = [:]
        for row in rows {
            if byName[row.workspace.name] == nil { order.append(row.workspace.name) }
            byName[row.workspace.name, default: []].append(row)
        }
        return order.map { (name: $0, rows: byName[$0] ?? []) }
    }

    static func accessibilityLabel(_ row: ScheduledRow) -> String {
        "\(row.task.name), \(row.workspace.name), \(ScheduledStyle.next(row.task))"
    }

    var body: some View {
        let groups = Self.groups(store.rows)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: m.pt(10)) {
                SidebarModeHeader(refresh: { store.refresh() })
                SidebarNewRow(title: "New task", systemImage: "plus", shortcut: "⌘N") { store.requestNewTask() }
                    .disabled(store.workspaces.isEmpty)
            }
            .padding(.bottom, m.pt(14))
            .modifier(SidebarHeaderTop())
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(groups, id: \.name) { group in
                        Text(verbatim: group.name)
                            .font(.dm(11, weight: .medium))
                            .foregroundStyle(Color.dmMuted)
                            .padding(.horizontal, m.pt(16))
                            .padding(.top, m.pt(10))
                            .padding(.bottom, m.pt(4))
                        ForEach(group.rows) { row in
                            taskRow(row)
                        }
                    }
                    if groups.isEmpty, store.hasLoaded {
                        Text(verbatim: "No scheduled tasks yet")
                            .font(.dm(12))
                            .foregroundStyle(Color.dmMuted)
                            .padding(.horizontal, m.pt(16))
                            .padding(.top, m.pt(10))
                    }
                }
                .padding(.bottom, m.pt(10))
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1, in: groups) }
            .onKeyPress(.upArrow) { move(-1, in: groups) }
            .accessibilityLabel("Scheduled tasks")
            .accessibilityHint("Up and down arrows move between tasks")
            footer
        }
        .background(Color.dmSidebarBg)
        .onAppear { store.appear() }
    }

    private func move(_ step: Int, in groups: [(name: String, rows: [ScheduledRow])]) -> KeyPress.Result {
        let ids = groups.flatMap(\.rows).map(\.id)
        guard let next = ChatListNavigation.neighbor(of: store.selectedID, in: ids, step: step) else { return .ignored }
        store.selectedID = next
        return .handled
    }

    private func taskRow(_ row: ScheduledRow) -> some View {
        HStack(spacing: m.pt(8)) {
            Circle()
                .fill(ScheduledStyle.color(row.task.lastRun?.status))
                .frame(width: m.pt(DMIconSize.dot) - 1, height: m.pt(DMIconSize.dot) - 1)
            Text(verbatim: row.task.name)
                .font(.dm(13))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
            Spacer(minLength: m.pt(6))
            Text(verbatim: ScheduledStyle.next(row.task))
                .font(.dm(10.5))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
        }
        .opacity(row.task.paused || row.task.done ? 0.7 : 1)
        .padding(.horizontal, m.row.horizontal)
        .padding(.vertical, m.row.vertical)
        .background(DMRowBackground(selected: row.id == store.selectedID))
        .padding(.horizontal, m.row.outer)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = row.id }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(row))
        .accessibilityAddTraits(row.id == store.selectedID ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.selectedID = row.id }
        .demoClickTarget("schedule-sidebar:\(row.id)")
    }

    private var footer: some View {
        HStack(spacing: 0) {
            DMIconButton(
                systemImage: "chart.bar", size: DMMetrics.baseFontSize, hitSize: DMHitSize.footer, fillsWidth: true
            ) { model.showPage(.stats) }
                .help("Stats")
                .accessibilityLabel("Stats")
            if model.hasCaddyMachine {
                DMIconButton(
                    systemImage: "globe", size: DMMetrics.baseFontSize, hitSize: DMHitSize.footer, fillsWidth: true
                ) { model.showPage(.subdomains) }
                    .help("Published apps")
                    .accessibilityLabel("Published apps")
            }
            DMIconButton(
                systemImage: "gearshape", size: DMMetrics.baseFontSize, hitSize: DMHitSize.footer, fillsWidth: true
            ) { model.openSettings(.general) }
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal, m.space.lg)
        .padding(.vertical, m.space.md)
    }
}
