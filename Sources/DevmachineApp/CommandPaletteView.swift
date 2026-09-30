import SwiftUI
import DevmachineCore

struct CommandPaletteView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var caddy: CaddyStore
    @EnvironmentObject private var health: HealthCheckStore
    @EnvironmentObject private var savedCommands: RecentCommandStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var filesStore: FilesStore
    @EnvironmentObject private var recents: PaletteRecentsStore
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var context: PaletteContext {
        var context = PaletteContext()
        context.workspaces = model.visibleWorkspaces
        context.sessions = model.paletteItems()
        context.localSessions = model.localSessions
        context.launchOptions = harnessSettingsFacade.launchOptions(for: settingsStore.settings ?? .empty)
        context.savedCommands = Dictionary(
            uniqueKeysWithValues: model.sidebarWorkspaces.map { ($0.alias, savedCommands.recents(for: $0.alias)) })
        context.machines = stats.machines.map(\.name)
        context.hasCaddyMachine = model.hasCaddyMachine
        context.subdomainsMachine = caddy.dnsMachine ?? stats.machines.first?.name
        context.currentTerminal = model.currentTerminalKind
        context.endableSession = model.endableSession
        context.currentWorkspaceAlias = model.currentWorkspaceAlias
        context.activePage = model.activePage
        return context
    }

    private var sections: [PaletteSection] {
        let context = context
        return PaletteRanker.sections(
            CommandRegistry.commands(in: context), query: query, mru: recents.mru,
            currentWorkspace: context.currentWorkspace?.name)
    }

    private var dispatcher: PaletteDispatcher {
        PaletteDispatcher(
            model: model, stats: stats, sites: caddy, health: health, savedCommands: savedCommands,
            recents: recents,
            system: AppPaletteSystem(openFiles: { alias in
                filesStore.open(.host(alias: alias))
                openWindow(id: "files")
            }))
    }

    var body: some View {
        let sections = sections
        let flat = sections.flatMap(\.commands)
        VStack(spacing: 0) {
            DMSearchField(
                prompt: "Search sessions, pages and actions…", text: $query, focus: $focused,
                fontSize: 15, iconSize: 13, spacing: 10, iconColor: .secondary)
            .onSubmit { run(flat) }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            DMSectionLabel(text: section.category.title.uppercased())
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                            ForEach(section.commands) { command in
                                let position = flat.firstIndex { $0.id == command.id } ?? 0
                                row(command, selected: position == index)
                                    .id(command.id)
                                    .onTapGesture { dispatcher.perform(command) }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 420)
                .onChange(of: index) { _, new in
                    if new < flat.count { withAnimation { proxy.scrollTo(flat[new].id) } }
                }
            }
        }
        .frame(width: 600)
        .dmGlass(radius: DMRadius.panel)
        .shadow(radius: 30, y: 12)
        .onAppear {
            focused = true
            index = 0
            query = DemoSnapshots.paletteInitialQuery
        }
        .onChange(of: query) { _, _ in index = 0 }
        .onKeyPress(.downArrow) { index = min(index + 1, max(flat.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
        .onKeyPress(.return) { run(flat); return .handled }
        .onKeyPress(.escape) { model.showCommandPalette = false; return .handled }
    }

    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            icon(command)
                .frame(width: 18)
            Text(verbatim: command.title)
                .font(.dm(13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(verbatim: command.subtitle)
                .font(.dm(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let shortcut = command.shortcut {
                DMKeyCap(key: shortcut)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            DMRowBackground(selected: selected, cornerRadius: DMRadius.control, selectedColor: .dmActive))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icon(_ command: PaletteCommand) -> some View {
        if command.category == .session || command.action.opensSession {
            HStack(spacing: 3) {
                if command.badges.isEmpty {
                    Image(systemName: "circle")
                        .foregroundStyle(Color.dmMuted)
                } else {
                    ForEach(command.badges) { badge in
                        Image(systemName: badge.systemImage)
                            .foregroundStyle(badge.color)
                            .help(badge.helpText)
                    }
                }
            }
            .font(.dm(7))
        } else {
            Image(systemName: command.systemImage)
                .font(.dm(12))
                .foregroundStyle(Color.dmMuted)
        }
    }

    private func run(_ flat: [PaletteCommand]) {
        guard index < flat.count else { return }
        dispatcher.perform(flat[index])
    }
}

private extension PaletteAction {
    var opensSession: Bool {
        if case .openSession = self { return true }
        return false
    }
}
