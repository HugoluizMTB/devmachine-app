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
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.workspaces.enumerated()), id: \.element.id) { index, ws in
                        groupHeader(
                            ws.name,
                            alias: ws.alias,
                            offline: model.offlineAliases.contains(ws.alias),
                            action: { model.newSession(alias: ws.alias) },
                            extraTopSpacing: index > 0
                        )
                        ForEach(model.sessionsByAlias[ws.alias] ?? []) { s in
                            sessionRow(alias: ws.alias, session: s)
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
        HStack(spacing: 8) {
            DMRow(
                systemImage: "sparkle",
                iconColor: .orange,
                iconSize: 9,
                title: "operador",
                selected: model.selection == .operador,
                outerHorizontalPadding: 0,
                fillWidth: false,
                tap: { model.selection = .operador }
            )
            .fixedSize()

            Spacer(minLength: 4)

            Button {
                model.showPage(.stats)
            } label: {
                Image(systemName: "chart.bar")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Stats")

            Button {
                model.showPage(.subdomains)
            } label: {
                Image(systemName: "globe")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Subdomains")

            Button {
                model.showPage(.setup)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Settings (⌘,)")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed = true }
            } label: {
                Image(systemName: "sidebar.left")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dmMuted)
            .help("Fechar sidebar (⌘B)")
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
                    .font(.system(size: 11, weight: .semibold))
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
                .help("Atualizar")

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
                .help("Nova sessão…")
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
        extraTopSpacing: Bool
    ) -> some View {
        DMSection(
            padding: EdgeInsets(top: extraTopSpacing ? 16 : 4, leading: 10, bottom: 4, trailing: 10),
            label: {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
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
                .font(.system(size: 11))
                .help("Workspace home")

                Button {
                    openFiles(alias: alias)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Color.dmMuted)
                .font(.system(size: 11))
                .help("Files…")

                if let action {
                    Button(action: action) {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.dmMuted)
                    .font(.system(size: 11))
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
                Button("Apagar \(model.selectedSessions.count) sessões", role: .destructive) {
                    model.pendingBulkDelete = Array(model.selectedSessions)
                }
            } else {
                Button("Abrir") {
                    model.clickSession(ref)
                }
                Button("Renomear…") {
                    model.pendingRename = (alias: alias, old: s.name)
                }
                Button("Apagar", role: .destructive) {
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
                AnyView(Text("\(count)").font(.system(size: 11)).foregroundStyle(Color.dmMuted))
            }
        )
    }
}
