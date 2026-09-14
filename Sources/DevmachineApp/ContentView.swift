import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var dragStartWidth: CGFloat? = nil
    @State private var contextDragStartWidth: CGFloat? = nil

    private var isClaudeSession: Bool {
        guard case let .session(alias, name) = model.selection else { return false }
        return model.sessionsByAlias[alias]?.first(where: { $0.name == name })?.hasClaude ?? false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Setup owns the whole window: no sidebar, no context, just the
            // photo and one card, so first run reads as a welcome, not a page.
            if model.activePage == .setup {
                SetupPage()
            } else {
                mainRow
                if model.sidebarCollapsed { collapsedSidebarButton }
            }
            shortcutButtons
        }
        .background(Color.dmSidebarBg)
        .overlay {
            if model.showCommandPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { model.showCommandPalette = false }
                    CommandPaletteView()
                        .environmentObject(model)
                        .padding(.top, 110)
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(model.activeTasks) { task in
                    DMToastCard(task: task)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(18)
            .animation(.easeInOut(duration: 0.2), value: model.activeTasks)
        }
        .onAppear {
            model.settings = settingsStore.settings
            if settingsStore.isConfigured {
                model.loadWorkspaces()
            } else {
                model.activePage = .setup
            }
        }
        .onReceive(settingsStore.$settings) { model.settings = $0 }
        .sheet(isPresented: $model.showShortcuts) {
            ShortcutsSheet().environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { model.pendingNewSessionAlias != nil },
            set: { if !$0 { model.pendingNewSessionAlias = nil } }
        )) {
            NewSessionSheet(alias: model.pendingNewSessionAlias ?? "")
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { model.pendingRename != nil },
            set: { if !$0 { model.pendingRename = nil } }
        )) {
            if let pending = model.pendingRename {
                RenameSheet(alias: pending.alias, oldName: pending.old)
                    .environmentObject(model)
            }
        }
        .confirmationDialog(
            "Delete session \(model.pendingDelete?.name ?? "")? This kills its tmux session.",
            isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { if !$0 { model.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pending = model.pendingDelete {
                    model.deleteSession(alias: pending.alias, name: pending.name)
                }
            }
            Button("Cancel", role: .cancel) { model.pendingDelete = nil }
        }
        .confirmationDialog(
            "Delete \(model.pendingBulkDelete?.count ?? 0) sessions? This kills their tmux sessions.",
            isPresented: Binding(
                get: { model.pendingBulkDelete != nil },
                set: { if !$0 { model.pendingBulkDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pending = model.pendingBulkDelete {
                    model.deleteSessions(pending)
                }
            }
            Button("Cancel", role: .cancel) { model.pendingBulkDelete = nil }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: model.sidebarCollapsed ? 0 : model.sidebarWidth)
                .clipped()
            if !model.sidebarCollapsed {
                sidebarDivider
            }
            centerPane
            if isClaudeSession && model.activePage == nil {
                contextArea
            }
        }
    }

    // A real 6pt drag column (layout element, not an overlay): an overlay spilled
    // onto the sidebar's right edge and stole its clicks.
    private var sidebarDivider: some View {
        ResizeHandle(
            onDrag: { dx in
                let base = dragStartWidth ?? model.sidebarWidth
                if dragStartWidth == nil { dragStartWidth = base }
                model.setSidebarWidth(base + dx)
            },
            onEnd: { dragStartWidth = nil }
        )
    }

    @ViewBuilder
    private var centerPane: some View {
        ZStack {
            // Under the hidden title bar too: the wallpaper and the cards reach
            // the window's top edge, no content-colored band above them.
            MainPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.dmContentBg)
                .ignoresSafeArea(edges: .top)
            if let page = model.activePage {
                PageHost(page: page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dmContentBg)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var contextArea: some View {
        if model.contextCollapsed {
            ContextCollapsedStrip()
        } else {
            ResizeHandle(
                onDrag: { dx in
                    let base = contextDragStartWidth ?? model.contextWidth
                    if contextDragStartWidth == nil { contextDragStartWidth = base }
                    model.setContextWidth(base - dx)
                },
                onEnd: { contextDragStartWidth = nil }
            )
            ContextPanel(store: model.context)
                .frame(width: model.contextWidth)
        }
    }

    private var collapsedSidebarButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed = false }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(9)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
                .shadow(radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("Open sidebar (⌘B)")
        .padding(.top, 18)
        .padding(.leading, 14)
    }

    private var shortcutButtons: some View {
        ZStack {
            Button("") {
                withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed.toggle() }
            }
            .keyboardShortcut("b", modifiers: .command)
            Button("") { model.showCommandPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
            Button("") {
                withAnimation(.easeInOut(duration: 0.18)) { model.contextCollapsed.toggle() }
            }
            .keyboardShortcut("j", modifiers: .command)
            Button("") { model.toggleMaximize() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
        }
        .hidden()
        .frame(width: 0, height: 0)
    }
}

private struct PageHost: View {
    let page: AppPage

    var body: some View {
        switch page {
        case .setup: EmptyView()
        case .stats: StatsView()
        case .subdomains: SubdomainsView()
        case .stack(let refs): StackGridView(refs: refs).ignoresSafeArea(edges: .top)
        }
    }
}

private struct MainPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            WallpaperBackground(style: .ambient)

            // Only the selected terminal is mounted: the registry owns the process,
            // so an unmounted one keeps running and re-attaches on the next select.
            // A stacked session is mounted by the grid instead — mounting it here as
            // well would pull the shared view out of its grid cell.
            if let selected = model.selection, !isStacked(selected) {
                terminal(for: selected)
            }
            if model.selection == nil {
                HomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func isStacked(_ item: SidebarItem) -> Bool {
        guard case let .session(alias, name) = item else { return false }
        return model.isStacked(SessionRef(alias: alias, name: name))
    }

    @ViewBuilder
    private func terminal(for item: SidebarItem) -> some View {
        Group {
            switch item {
            case .opsShell:
                TerminalPaneView(kind: .opsShell, translucent: true)
            case let .session(alias, name):
                TerminalPaneView(kind: .remote(alias: alias, session: name), translucent: true)
            }
        }
        .id(key(item))
        .floatingCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FloatingCardLayout.margin)
    }

    private func key(_ item: SidebarItem) -> String {
        switch item {
        case .opsShell: return "opsShell"
        case let .session(alias, name): return "\(alias)/\(name)"
        }
    }
}

private struct RenameSheet: View {
    @EnvironmentObject var model: AppModel
    let alias: String
    let oldName: String
    @State private var name: String

    init(alias: String, oldName: String) {
        self.alias = alias
        self.oldName = oldName
        _name = State(initialValue: oldName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(oldName)").font(.headline)
            TextField("new name", text: $name).frame(width: 240)
            HStack {
                Spacer()
                Button("Cancel") { model.pendingRename = nil }
                Button("Rename") { model.renameSession(alias: alias, old: oldName, new: name) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

private struct NewSessionSheet: View {
    @EnvironmentObject var model: AppModel
    let alias: String
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New session in \(alias)").font(.headline)
            TextField("name", text: $name).frame(width: 240)
            HStack {
                Spacer()
                Button("Cancel") { model.pendingNewSessionAlias = nil }
                Button("Create") { model.confirmNewSession(alias: alias, name: name) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
