import SwiftUI
import DevmachineCore

struct CommandPaletteView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var model: AppModel
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var caddy: CaddyStore
    @EnvironmentObject private var health: HealthCheckStore
    @EnvironmentObject private var savedCommands: RecentCommandStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var filesStore: FilesStore
    @EnvironmentObject private var recents: PaletteRecentsStore
    @EnvironmentObject private var updates: UpdateController
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var chats = ChatStore.shared
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var context: PaletteContext {
        var context = PaletteContext()
        context.workspaces = model.visibleWorkspaces
        context.sessions = model.paletteItems()
        context.localSessions = model.localSessions
        context.launchOptions = harnessSettingsFacade.launchOptions(for: settingsStore.settings ?? .empty, on: .remote)
        context.localLaunchOptions = harnessSettingsFacade.launchOptions(
            for: settingsStore.settings ?? .empty, on: .thisMac)
        context.savedCommands = Dictionary(
            uniqueKeysWithValues: model.sidebarWorkspaces.map { ($0.alias, savedCommands.recents(for: $0.alias)) })
        context.machines = stats.machines.map(\.name)
        context.hasCaddyMachine = model.hasCaddyMachine
        context.subdomainsMachine = caddy.dnsMachine ?? stats.machines.first?.name
        context.currentTerminal = model.currentTerminalKind
        context.endableSession = model.endableSession
        context.currentWorkspaceAlias = model.currentWorkspaceAlias
        context.activePage = model.activePage
        context.cliUpdate = updates.cliNotice
        context.chats = chats.visibleChats
        context.chatSettings = chats.settings
        context.chatConfig = chats.config
        context.chatWorkspaces = chats.workspaces
        context.cliLogExists = LogFiles.shared.cliLogExists
        context.historyExists = LogFiles.shared.historyExists
        context.previewTargets = PreviewTargetsStore.shared.knownTargets().map {
            PalettePreviewGroup(place: $0.place, targets: $0.targets)
        }
        return context
    }

    private var sections: [PaletteSection] {
        let context = context
        return PaletteRanker.sections(
            CommandRegistry.commands(in: context), query: query, mru: recents.mru,
            currentWorkspace: context.currentWorkspace?.name, inChats: model.appMode == .chats)
    }

    private var dispatcher: PaletteDispatcher {
        PaletteDispatcher(
            model: model, stats: stats, sites: caddy, health: health, savedCommands: savedCommands,
            updates: updates, recents: recents,
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
            .padding(.horizontal, m.space.xl)
            .padding(.vertical, m.pt(14))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: m.space.xxs) {
                        ForEach(sections) { section in
                            DMSectionLabel(text: section.category.title.uppercased())
                                .padding(.horizontal, m.pt(10))
                                .padding(.top, m.space.md)
                                .padding(.bottom, m.space.xxs)
                            ForEach(section.commands) { command in
                                let position = flat.firstIndex { $0.id == command.id } ?? 0
                                row(command, selected: position == index)
                                    .id(command.id)
                                    .onTapGesture { dispatcher.perform(command) }
                            }
                        }
                    }
                    .padding(m.space.sm)
                }
                .frame(maxHeight: m.pt(420))
                .onChange(of: index) { _, new in
                    if new < flat.count { withAnimation { proxy.scrollTo(flat[new].id) } }
                }
            }
        }
        .frame(width: m.card.palette)
        .dmGlass(radius: DMRadius.panel)
        .shadow(radius: m.pt(30), y: m.pt(12))
        .task { await chats.refresh() }
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
        HStack(spacing: m.pt(10)) {
            icon(command)
                .frame(width: m.pt(18))
            Text(verbatim: command.title)
                .font(.dm(13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(verbatim: command.subtitle)
                .font(.dm(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: m.space.md)
            if let badge = command.badgeText {
                DMPill(text: badge, color: .accentColor)
            }
            if let shortcut = command.shortcut {
                DMKeyCap(key: shortcut)
            }
        }
        .padding(.horizontal, m.pt(10))
        .padding(.vertical, m.pt(7))
        .background(
            DMRowBackground(selected: selected, cornerRadius: DMRadius.control, selectedColor: .dmActive))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icon(_ command: PaletteCommand) -> some View {
        if let harness = command.harness {
            ChatHarnessGlyph(harness: harness, size: 13)
        } else if command.category == .session || command.action.opensSession {
            HStack(spacing: m.pt(3)) {
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
