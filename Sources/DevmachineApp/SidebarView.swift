import SwiftUI
import AppKit
import DevmachineCore

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var filesStore: FilesStore
    @EnvironmentObject var customCommandsStore: CustomCommandStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.sidebarWorkspaces.enumerated()), id: \.element.id) { index, ws in
                        groupHeader(
                            ws.name,
                            alias: ws.alias,
                            offline: !ws.isLocal && model.offlineAliases.contains(ws.alias),
                            action: ws.isLocal ? pickLocalFolder : { model.newSession(alias: ws.alias) },
                            filesButton: !ws.isLocal,
                            extraTopSpacing: index > 0
                        )
                        if ws.isLocal {
                            ForEach(model.localSessions) { s in
                                localSessionRow(session: s)
                            }
                        } else {
                            ForEach(model.sessionsByAlias[ws.alias] ?? []) { s in
                                sessionRow(alias: ws.alias, session: s)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            footerRow
        }
        .background(Color.dmSidebarBg)
    }

    private var footerRow: some View {
        HStack(spacing: 0) {
            footerButton("chart.bar") { model.showPage(.stats) }
                .help("Stats")
            footerButton("globe") { model.showPage(.subdomains) }
                .help("Subdomains")
            footerButton("command") { model.showPage(.customCommands) }
                .help("Custom commands")
            footerButton("gearshape") { model.showPage(.setup) }
                .help("Settings (⌘,)")
            footerButton("sidebar.left") {
                withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed = true }
            }
            .help("Close sidebar (⌘B)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func footerButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        DMIconButton(
            systemImage: systemImage, hitSize: DMHitSize.footer, fillsWidth: true,
            action: action)
    }

    private var topBar: some View {
        DMSection(
            headerSpacing: 8,
            padding: EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12),
            label: {
                Text("WORKSPACES")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                    .kerning(0.8)
            },
            trailing: {
                DMIconButton(systemImage: "arrow.clockwise") { model.refreshAll() }
                    .help("Refresh")

                Menu {
                    ForEach(model.workspaces) { ws in
                        Button(ws.name) { model.newSession(alias: ws.alias) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(Color.dmMuted)
                .help("New session…")
            }
        )
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 12)
        }
    }

    @ViewBuilder
    private func groupHeader(
        _ title: String,
        alias: String,
        offline: Bool,
        action: (() -> Void)?,
        filesButton: Bool = true,
        extraTopSpacing: Bool
    ) -> some View {
        DMSection(
            padding: EdgeInsets(top: extraTopSpacing ? 16 : 4, leading: 10, bottom: 4, trailing: 10),
            label: {
                Text(title)
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                if offline {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .help("Offline")
                }
            },
            trailing: {
                DMIconButton(
                    systemImage: model.isWorkspaceStacked(alias) ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2",
                    size: 11,
                    tint: model.isWorkspaceStacked(alias) ? Color.accentColor : Color.dmMuted,
                    hitSize: DMHitSize.header
                ) { model.stackWorkspace(alias) }
                .help("Workspace home")

                if filesButton {
                    DMIconButton(systemImage: "folder", size: 11, hitSize: DMHitSize.header) {
                        openFiles(alias: alias)
                    }
                    .help("Files…")
                }

                if let action {
                    newSessionButton(alias: alias, action: action)
                }
            }
        )
        .contextMenu {
            Button("Open workspace home") { model.stackWorkspace(alias) }
            Button("Files…") { openFiles(alias: alias) }
        }
    }

    /// A plain "+" with no custom command applicable here, else a menu
    /// offering "New session" plus every custom command in scope for this
    /// workspace (or this Mac).
    @ViewBuilder
    private func newSessionButton(alias: String, action: @escaping () -> Void) -> some View {
        let isLocal = alias == Workspace.local.alias
        let applicable = customCommandsStore.applicable(toLocal: isLocal, alias: alias)
        if applicable.isEmpty {
            DMIconButton(systemImage: "plus", size: 11, hitSize: DMHitSize.header, action: action)
        } else {
            Menu {
                Button("New session", action: action)
                Divider()
                ForEach(applicable) { command in
                    Button {
                        model.runCustomCommand(command, forWorkspaceAlias: alias)
                    } label: {
                        Label(command.name, systemImage: command.icon.systemImage)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: DMHitSize.header.width, height: DMHitSize.header.height)
            .help("New session…")
        }
    }

    private func openFiles(alias: String) {
        filesStore.open(.host(alias: alias))
        openWindow(id: "files")
    }

    private func localSessionRow(session s: LocalSession) -> some View {
        let item = SidebarItem.localSession(name: s.handle, path: s.path)
        let isOpen = model.activePage == nil && model.selection == item
        let live = model.localSessionIsLive(s)
        return row(
            title: s.name,
            badges: model.badges(for: s),
            // A session the multiplexer does not have yet is a name waiting for
            // a shell, so it carries no client count.
            windows: live ? 1 : nil,
            selected: isOpen
        )
            .contentShape(Rectangle())
            .onTapGesture { model.clickLocalSession(item) }
            .help(live ? s.path : "\(s.path) — not started")
            .contextMenu {
                Button("Rename…") {
                    model.pendingLocalRename = (handle: s.handle, current: s.name)
                }
                if s.handle != Workspace.operatorSession {
                    Button("Remove", role: .destructive) {
                        model.askToRemoveLocalSession(handle: s.handle)
                    }
                }
            }
    }

    /// Asks for the folder the shell starts in. The name comes from the folder,
    /// so there is nothing else to fill in.
    private func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addLocalSession(path: url.path)
    }

    private func sessionRow(alias: String, session s: TmuxSession) -> some View {
        let ref = SessionRef(alias: alias, name: s.name)
        // A page (stats/subdomains/stack) covers the terminal, so the old
        // selection is not "where you are" — only stacked sessions are.
        let isOpen = model.activePage == nil && model.selection == .session(alias: alias, name: s.name)
        let isMultiSelected = model.selectedSessions.contains(ref)
        return row(
            title: s.name,
            badges: model.badges(for: s),
            windows: s.windows,
            selected: isOpen || isMultiSelected || model.isStacked(ref)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            if mods.contains(.command) {
                model.cmdClickSession(ref)
            } else if mods.contains(.shift) {
                model.shiftClickSession(ref)
            } else {
                model.clickSession(ref)
            }
        }
        .contextMenu {
            if model.selectedSessions.count > 1 && model.selectedSessions.contains(ref) {
                Button("Stack to Home") {
                    model.stackSessions(Array(model.selectedSessions))
                }
                Button("Delete \(model.selectedSessions.count) sessions", role: .destructive) {
                    model.pendingBulkDelete = Array(model.selectedSessions)
                }
            } else {
                Button("Open") {
                    model.clickSession(ref)
                }
                Button("Rename…") {
                    model.pendingRename = (alias: alias, old: s.name)
                }
                Button("Delete", role: .destructive) {
                    model.pendingDelete = (alias: alias, name: s.name)
                }
            }
        }
    }

    /// Harness badges appear before the client count only under the pointer: a
    /// sidebar full of marks is noise, while hover makes one row easy to check.
    private func row(
        title: String,
        badges: [HarnessBadgePresentation],
        windows: Int?,
        selected: Bool
    ) -> some View {
        DMRow(
            title: title,
            selected: selected,
            trailing: windows.map { count in
                AnyView(Text(verbatim: "\(count)").font(.dm(11)).foregroundStyle(Color.dmMuted))
            },
            trailingHover: badges.isEmpty ? nil : AnyView(
                HStack(spacing: 4) {
                    ForEach(badges) { badge in
                        Image(systemName: badge.systemImage)
                            .font(.dm(5))
                            .foregroundStyle(badge.color)
                            .help(badge.helpText)
                    }
                }
            )
        )
    }
}
