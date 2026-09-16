import SwiftUI
import AppKit
import DevmachineCore

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var filesStore: FilesStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            connectingBar
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

    /// One bar for whatever short job is running: sending a file wins over the
    /// sweep, since it is the thing you just started.
    @ViewBuilder
    private var connectingBar: some View {
        if let transfer = model.transfer {
            progressStrip(label: transfer.label, done: transfer.done, total: transfer.total,
                          color: .blue)
        } else if let label = model.connectingLabel {
            progressStrip(label: label, done: model.sweepDone, total: model.sweepTotal,
                          color: .orange)
        }
    }

    private func progressStrip(label: String, done: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            DMProgressBar(done: done, total: total, fillColor: color)
            Text(verbatim: label)
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    private var footerRow: some View {
        HStack(spacing: 0) {
            Button {
                model.showPage(.stats)
            } label: {
                Image(systemName: "chart.bar")
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Stats")

            Button {
                model.showPage(.subdomains)
            } label: {
                Image(systemName: "globe")
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Subdomains")

            Button {
                model.showPage(.setup)
            } label: {
                Image(systemName: "gearshape")
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Settings (⌘,)")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed = true }
            } label: {
                Image(systemName: "sidebar.left")
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Close sidebar (⌘B)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                Button {
                    model.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dmMuted)
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
                Button {
                    model.stackWorkspace(alias)
                } label: {
                    Image(systemName: model.isWorkspaceStacked(alias) ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2")
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.isWorkspaceStacked(alias) ? Color.accentColor : Color.dmMuted)
                .font(.dm(11))
                .help("Workspace home")

                if filesButton {
                    Button {
                        openFiles(alias: alias)
                    } label: {
                        Image(systemName: "folder")
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.dmMuted)
                    .font(.dm(11))
                    .help("Files…")
                }

                if let action {
                    Button(action: action) {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.dmMuted)
                    .font(.dm(11))
                }
            }
        )
        .contextMenu {
            Button("Open workspace home") { model.stackWorkspace(alias) }
            Button("Files…") { openFiles(alias: alias) }
        }
    }

    private func openFiles(alias: String) {
        filesStore.open(alias: alias)
        openWindow(id: "files")
    }

    private func localSessionRow(session s: LocalSession) -> some View {
        let item = SidebarItem.localSession(name: s.name, path: s.path)
        let isOpen = model.activePage == nil && model.selection == item
        return row(title: s.name, claude: false, windows: 1, selected: isOpen)
            .contentShape(Rectangle())
            .onTapGesture { model.selection = item }
            .help(s.path)
            .contextMenu {
                if s.name != Workspace.operatorSession {
                    Button("Remove") { model.removeLocalSession(name: s.name) }
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
            claude: s.hasClaude,
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

    private func row(title: String, claude: Bool, windows: Int?, selected: Bool) -> some View {
        DMRow(
            systemImage: claude ? "circle.fill" : "circle",
            iconColor: claude ? .orange : .dmMuted,
            title: title,
            selected: selected,
            trailing: windows.map { count in
                AnyView(Text("\(count)").font(.dm(11)).foregroundStyle(Color.dmMuted))
            }
        )
    }
}
