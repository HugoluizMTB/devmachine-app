import SwiftUI
import DevmachineCore

/// Settings' "Custom commands" central page: list, add, edit, delete, reorder
/// a user's own launch commands. Its own store, its own file — `AppSettings`
/// never carries this data.
struct CustomCommandsPage: View {
    @EnvironmentObject var store: CustomCommandStore
    @EnvironmentObject var model: AppModel
    @State private var editing: CustomCommand?
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
        .sheet(isPresented: $showAdd) {
            CustomCommandEditor(existing: nil, remoteWorkspaces: remoteWorkspaces) { command in
                store.add(command)
            }
        }
        .sheet(item: $editing) { command in
            CustomCommandEditor(existing: command, remoteWorkspaces: remoteWorkspaces) { updated in
                store.update(updated)
            }
        }
    }

    private var remoteWorkspaces: [Workspace] {
        model.visibleWorkspaces.filter { !$0.isLocal }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Custom commands")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            Spacer()
            DMIconButton(systemImage: "plus", tint: nil) { showAdd = true }
                .help("Add custom command")
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        if store.commands.isEmpty {
            DMStatusView(kind: .empty(
                systemImage: "command",
                text: "No custom commands yet. Add one to launch it in a new session."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.commands.enumerated()), id: \.element.id) { index, command in
                        row(command, index: index)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func row(_ command: CustomCommand, index: Int) -> some View {
        DMRow(
            systemImage: command.icon.systemImage,
            iconColor: .dmMuted,
            title: command.name,
            trailing: AnyView(rowTrailing(command, index: index))
        )
        .contextMenu {
            Button("Edit…") { editing = command }
            Button("Delete", role: .destructive) { store.remove(command.id) }
        }
    }

    private func rowTrailing(_ command: CustomCommand, index: Int) -> some View {
        HStack(spacing: 6) {
            Text(command.command)
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
            Text(scopeLabel(command.scope))
                .font(.dm(10))
                .foregroundStyle(Color.dmMuted)
            if let slot = command.shortcutSlot {
                DMKeyCap(key: "⌘⌥\(slot)")
            }
            DMIconButton(systemImage: "chevron.up", size: 10, tint: nil) {
                store.move(fromOffsets: IndexSet(integer: index), toOffset: max(0, index - 1))
            }
            .disabled(index == 0)
            .help("Move up")
            DMIconButton(systemImage: "chevron.down", size: 10, tint: nil) {
                store.move(fromOffsets: IndexSet(integer: index), toOffset: min(store.commands.count, index + 2))
            }
            .disabled(index == store.commands.count - 1)
            .help("Move down")
            DMIconButton(systemImage: "pencil", size: 10, tint: nil) { editing = command }
                .help("Edit")
            DMIconButton(systemImage: "trash", size: 10, tint: .red) { store.remove(command.id) }
                .help("Delete")
        }
    }

    private func scopeLabel(_ scope: CustomCommandScope) -> String {
        switch scope {
        case .all: return "All"
        case .localOnly: return "This Mac"
        case let .workspaces(aliases): return aliases.isEmpty ? "No workspace" : aliases.joined(separator: ", ")
        }
    }
}

private struct CustomCommandEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existing: CustomCommand?
    let remoteWorkspaces: [Workspace]
    let onSave: (CustomCommand) -> Void

    @State private var name: String
    @State private var command: String
    @State private var icon: CustomCommandIcon
    @State private var scopeKind: ScopeKind
    @State private var selectedWorkspaces: Set<String>
    @State private var shortcutSlot: Int?

    private enum ScopeKind: String, CaseIterable {
        case all = "All"
        case local = "This Mac"
        case workspaces = "Workspaces"
    }

    init(existing: CustomCommand?, remoteWorkspaces: [Workspace], onSave: @escaping (CustomCommand) -> Void) {
        self.existing = existing
        self.remoteWorkspaces = remoteWorkspaces
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _command = State(initialValue: existing?.command ?? "")
        _icon = State(initialValue: existing?.icon ?? .terminal)
        _shortcutSlot = State(initialValue: existing?.shortcutSlot)
        switch existing?.scope ?? .all {
        case .all:
            _scopeKind = State(initialValue: .all)
            _selectedWorkspaces = State(initialValue: [])
        case .localOnly:
            _scopeKind = State(initialValue: .local)
            _selectedWorkspaces = State(initialValue: [])
        case let .workspaces(aliases):
            _scopeKind = State(initialValue: .workspaces)
            _selectedWorkspaces = State(initialValue: Set(aliases))
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var scope: CustomCommandScope {
        switch scopeKind {
        case .all: return .all
        case .local: return .localOnly
        case .workspaces: return .workspaces(Array(selectedWorkspaces))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "Add custom command" : "Edit custom command")
                .font(.dm(14, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            field("Name") {
                TextField("Claude (work)", text: $name).textFieldStyle(.roundedBorder)
            }

            field("Command") {
                TextField("CLAUDE_CONFIG_DIR=~/.claude-work claude", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            field("Icon") { iconPicker }

            field("Applies to") {
                Picker("", selection: $scopeKind) {
                    ForEach(ScopeKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if scopeKind == .workspaces {
                workspacePicker
            }

            field("Shortcut") { shortcutPicker }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(existing == nil ? "Add" : "Save") {
                    let base = existing ?? CustomCommand(name: "", command: "")
                    var result = base
                    result.name = name
                    result.command = command
                    result.icon = icon
                    result.scope = scope
                    result.shortcutSlot = shortcutSlot
                    onSave(result)
                    dismiss()
                }
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color.dmContentBg)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            content()
        }
    }

    private var iconPicker: some View {
        HStack(spacing: 6) {
            ForEach(CustomCommandIcon.allCases, id: \.self) { candidate in
                DMIconButton(
                    systemImage: candidate.systemImage,
                    tint: candidate == icon ? Color.accentColor : Color.dmMuted
                ) { icon = candidate }
            }
        }
    }

    private var workspacePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            if remoteWorkspaces.isEmpty {
                Text("No visible remote workspace is available.")
                    .font(.dm(11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(remoteWorkspaces) { ws in
                    Toggle(ws.name, isOn: Binding(
                        get: { selectedWorkspaces.contains(ws.alias) },
                        set: { on in
                            if on { selectedWorkspaces.insert(ws.alias) }
                            else { selectedWorkspaces.remove(ws.alias) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.dm(12))
                }
            }
        }
    }

    private var shortcutPicker: some View {
        Picker("", selection: $shortcutSlot) {
            Text("None").tag(Int?.none)
            ForEach(Array(CustomCommand.shortcutSlotRange), id: \.self) { slot in
                Text(verbatim: "⌘⌥\(slot)").tag(Int?.some(slot))
            }
        }
        .labelsHidden()
    }
}
