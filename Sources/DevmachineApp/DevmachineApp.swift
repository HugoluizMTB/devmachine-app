import SwiftUI
import DevmachineCore
import AppKit
import ClaudeUsageKit

@main
struct DevmachineApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var prStore = PRStore()
    @StateObject private var filesStore = FilesStore()
    @StateObject private var caddyStore = CaddyStore()
    @StateObject private var skillsStore = SkillsStore()
    @StateObject private var statsStore = StatsStore()
    @StateObject private var usageStore = ClaudeUsageStore()
    @StateObject private var settingsStore = SettingsStore.shared
    @StateObject private var wallpaperStore = WallpaperStore()

    var body: some Scene {
        // Single main window (Window, not WindowGroup) so the menubar "Open"
        // can reliably bring it to front via openWindow(id: "main").
        Window("Devmachine", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(filesStore)
                .environmentObject(skillsStore)
                .environmentObject(caddyStore)
                .environmentObject(statsStore)
                .environmentObject(usageStore)
                .environmentObject(settingsStore)
                .id(settingsStore.settings?.uiFontScale ?? Appearance.defaultUIFontScale)
                .onAppear { DMFont.scale = settingsStore.settings?.uiFontScale ?? 1 }
                .onChange(of: settingsStore.settings?.uiFontScale) { _, scale in
                    DMFont.scale = scale ?? 1
                }
                .environmentObject(wallpaperStore)
                .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.activePage = model.activePage == .setup ? nil : .setup }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { model.showShortcuts = true }
                    .keyboardShortcut("?", modifiers: .command)
            }
            // Real menu commands, not hidden buttons: a key equivalent in the
            // menu is handled before the key reaches the focused view, and the
            // terminal is a view from AppKit that holds first responder, which
            // is where the hidden-button shortcuts were being lost.
            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed.toggle() }
                }
                .keyboardShortcut("b", modifiers: .command)
                Button("Toggle Context") {
                    withAnimation(.easeInOut(duration: 0.18)) { model.contextCollapsed.toggle() }
                }
                .keyboardShortcut("j", modifiers: .command)
                Divider()
                Button("Find File…") { model.showFileSearch.toggle() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Go to Session…") { model.showCommandPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Maximize Pane") { model.toggleMaximize() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
        }

        Window("Files", id: "files") {
            FilesView()
                .environmentObject(filesStore)
        }
        .defaultSize(width: 520, height: 600)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(prStore)
                .environmentObject(usageStore)
                .environmentObject(model)
        } label: {
            MenuBarLabel(prStore: prStore)
        }
        .menuBarExtraStyle(.window)
    }
}

// Its own view so that a PRStore publish re-renders the label alone, instead of
// every Scene through the App's body.
struct MenuBarLabel: View {
    @ObservedObject var prStore: PRStore

    var body: some View {
        let mark = Text(verbatim: "❯_").font(.dm(13, weight: .bold, design: .monospaced))
        if prStore.openCount > 0 {
            HStack(spacing: 3) {
                mark
                Text(verbatim: "\(prStore.openCount)")
            }
        } else {
            mark
        }
    }
}
