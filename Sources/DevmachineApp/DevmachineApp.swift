import SwiftUI
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
        let mark = Text(verbatim: "❯_").font(.system(size: 13, weight: .bold, design: .monospaced))
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
