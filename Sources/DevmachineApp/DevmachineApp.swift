import SwiftUI
import DevmachineCore
import AppKit
import HarnessUsageKit

@main
struct DevmachineApp: App {
    private let harnessSettingsFacade: HarnessSettingsFacade
    @StateObject private var model = AppModel(cache: .shared)
    @StateObject private var prStore = PRStore()
    @StateObject private var filesStore = FilesStore()
    @StateObject private var caddyStore = CaddyStore(cache: .shared)
    @StateObject private var skillsStore = SkillsStore()
    @StateObject private var recentCommandStore = RecentCommandStore()
    @StateObject private var statsStore = StatsStore()
    @StateObject private var healthCheckStore = HealthCheckStore()
    @StateObject private var usageStore: HarnessUsageStore
    @StateObject private var settingsStore = SettingsStore.shared
    @StateObject private var wallpaperStore = WallpaperStore()
    @StateObject private var viewerStore = FileViewerStore()
    @StateObject private var fileTreeStore = FileTreeStore()
    @StateObject private var fileSearchStore = FileSearchStore()
    @StateObject private var paletteRecents = PaletteRecentsStore()
    @StateObject private var updates = UpdateController.live()

    init() {
        DemoSnapshots.applyScrollBarDefaultsIfNeeded()
        let facade = HarnessSettingsFacade()
        harnessSettingsFacade = facade
        // `DEVMACHINE_DEMO=1`: every store seeds itself from `DemoData` (see
        // `DemoMode.swift`) instead of reading real usage files, the CLI, or
        // ssh/gh. This is the one place that picks a provider list, so it is
        // also the one place that swaps in the demo providers.
        let providers: [any HarnessUsageProvider]
        if DemoMode.isActive {
            providers = DemoData.usageProviders
        } else {
            let settings = SettingsStore.shared.settings ?? .empty
            providers = facade.usageRegistrations(for: settings).map(\.provider)
        }
        _usageStore = StateObject(wrappedValue: HarnessUsageStore(providers: providers))
    }

    private var metrics: DMMetrics {
        DMMetrics(scale: settingsStore.settings?.uiFontScale ?? Appearance.defaultUIFontScale)
    }

    var body: some Scene {
        // Single main window (Window, not WindowGroup) so the menubar "Open"
        // can reliably bring it to front via openWindow(id: "main").
        Window("Devmachine", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(filesStore)
                .environmentObject(skillsStore)
                .environmentObject(recentCommandStore)
                .environmentObject(caddyStore)
                .environmentObject(statsStore)
                .environmentObject(healthCheckStore)
                .environmentObject(usageStore)
                .environmentObject(settingsStore)
                .environment(\.harnessSettingsFacade, harnessSettingsFacade)
                .environment(\.dmMetrics, metrics)
                .id(settingsStore.settings?.uiFontScale ?? Appearance.defaultUIFontScale)
                .onAppear { DMFont.scale = settingsStore.settings?.uiFontScale ?? 1 }
                .onAppear {
                    let stats = statsStore
                    caddyStore.statsSnapshot = { stats.state(for: $0)?.snapshot }
                    let readiness = MachineReadinessStore.shared
                    readiness.onConfigurationChanged = { [weak model] in
                        model?.reloadConfiguration()
                        stats.loadMachines()
                    }
                    readiness.onPrepared = { [weak model] machine in
                        model?.refreshWorkspaces(onMachine: machine)
                        stats.refresh()
                    }
                    HostKeyStore.shared.onTrusted = { [weak model] machine in
                        model?.hostKeyResolved(onMachine: machine)
                        stats.refresh()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    MachineReadinessStore.shared.requestCheckIfStale()
                }
                .onAppear {
                    DemoSnapshots.runIfNeeded(DemoSnapshots.Environment(
                        model: model, prStore: prStore, usageStore: usageStore, caddyStore: caddyStore,
                        settingsStore: settingsStore, wallpaperStore: wallpaperStore,
                        harnessSettingsFacade: harnessSettingsFacade))
                }
                .onChange(of: settingsStore.settings?.uiFontScale) { _, scale in
                    DMFont.scale = scale ?? 1
                }
                .onChange(of: settingsStore.settings?.enabledHarnesses) { _, _ in
                    let settings = settingsStore.settings ?? .empty
                    usageStore.configure(
                        providers: harnessSettingsFacade.usageRegistrations(for: settings).map(\.provider))
                    if usageStore.isObserved { usageStore.refresh(force: true) }
                }
                .environmentObject(wallpaperStore)
                .environmentObject(viewerStore)
                .environmentObject(fileTreeStore)
                .environmentObject(fileSearchStore)
                .environmentObject(paletteRecents)
                .environmentObject(updates)
                .onAppear {
                    updates.start()
                    #if DEBUG
                    RelaunchRehearsal.run(updates)
                    #endif
                }
                .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            // Replaces File > Close so ⌘W can ask to end the one session on
            // screen; every other case still closes the key window.
            CommandGroup(replacing: .saveItem) {
                Button("Close") { CloseCommand.perform(model: model) }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Session") {
                Button("Home") { model.goHome() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("New Session") { model.requestQuickSession() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("End Session…") { model.requestEndSession() }
                    .disabled(model.endableSession == nil)
                Divider()
                Button("Previous Session") { model.moveToPreviousSession() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Next Session") { model.moveToNextSession() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                Divider()
                Button("Back") { model.goBack() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                Button("Forward") { model.goForward() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.activePage = model.activePage == .setup ? nil : .setup }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("Check for Updates…") {
                    updates.checkNow()
                    model.openSettings(.about)
                }
                .disabled(updates.currentVersion == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { model.showShortcuts = true }
                    .keyboardShortcut("?", modifiers: .command)
            }
            // Real menu commands, not hidden buttons: a key equivalent in the
            // menu is handled before the key reaches the focused view, and the
            // terminal is a view from AppKit that holds first responder, which
            // is where the hidden-button shortcuts were being lost.
            CommandGroup(after: .sidebar) {
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
                Button("Command Palette…") { model.showCommandPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Maximize Pane") { model.toggleMaximize() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
        }

        Window("Files", id: "files") {
            FilesView()
                .environmentObject(filesStore)
                .environmentObject(viewerStore)
                .environmentObject(fileTreeStore)
                .environmentObject(model)
                .environment(\.dmMetrics, metrics)
        }
        .defaultSize(width: 520, height: 600)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(prStore)
                .environmentObject(usageStore)
                .environmentObject(model)
                .environment(\.harnessSettingsFacade, harnessSettingsFacade)
                .environment(\.dmMetrics, metrics)
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
