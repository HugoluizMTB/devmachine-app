import SwiftUI

struct ShortcutsSheet: View {
    @EnvironmentObject var model: AppModel

    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: [String]
        let action: String
    }

    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [Shortcut]
    }

    private let groups: [Group] = [
        Group(title: "Layout", items: [
            Shortcut(keys: ["⌘", "B"], action: "Toggle sidebar"),
            Shortcut(keys: ["⌘", "J"], action: "Toggle context panel"),
            Shortcut(keys: ["⌘", "K"], action: "Command palette: sessions, pages and actions"),
            Shortcut(keys: ["⌘", "?"], action: "This list"),
        ]),
        Group(title: "Sessions", items: [
            Shortcut(keys: ["⌘", "0"], action: "Home"),
            Shortcut(keys: ["⌘", "N"], action: "New session in the current folder"),
            Shortcut(keys: ["⌘", "⇧", "↑"], action: "Previous session"),
            Shortcut(keys: ["⌘", "⇧", "↓"], action: "Next session"),
            Shortcut(keys: ["⌘", "⇧", "←"], action: "Back"),
            Shortcut(keys: ["⌘", "⇧", "→"], action: "Forward"),
            Shortcut(keys: ["⌘", "⇧", "↩"], action: "Maximize the focused grid cell / back to its workspace grid"),
        ]),
        Group(title: "Sidebar", items: [
            Shortcut(keys: ["click"], action: "Open a session (click again → Home)"),
            Shortcut(keys: ["⌘", "click"], action: "Add/remove a session to the selection"),
            Shortcut(keys: ["⇧", "click"], action: "Select a range of sessions"),
            Shortcut(keys: ["right-click"], action: "Rename, delete, or Stack to Home"),
            Shortcut(keys: ["⊞"], action: "Workspace home: all its sessions in a grid"),
        ]),
        Group(title: "Stack grid", items: [
            Shortcut(keys: ["◀", "▶"], action: "Reorder a cell"),
            Shortcut(keys: ["⊞"], action: "Cycle cell size: auto → half → full"),
        ]),
        Group(title: "App", items: [
            Shortcut(keys: ["⌘", "Q"], action: "Quit"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.dm(14, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Spacer()
                Button("Close") { model.showShortcuts = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Rectangle().fill(Color.dmDivider).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title.uppercased())
                                .font(.dm(11, weight: .semibold))
                                .foregroundStyle(Color.dmMuted)
                                .kerning(0.8)
                            ForEach(group.items) { item in
                                HStack(spacing: 12) {
                                    HStack(spacing: 4) {
                                        ForEach(item.keys, id: \.self) { key in
                                            DMKeyCap(key: key)
                                        }
                                    }
                                    .frame(width: 130, alignment: .leading)
                                    Text(item.action)
                                        .font(.dm(12))
                                        .foregroundStyle(Color.dmRowText)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 520)
        .background(Color.dmContentBg)
    }
}
