import SwiftUI
import AppKit
import DevmachineCore
import HarnessUsageKit

/// Renders the website's screenshots straight out of the demo build: with
/// `DEVMACHINE_DEMO=1 DEVMACHINE_DEMO_SNAPSHOTS=<dir>` set, `runIfNeeded`
/// walks a fixed list of screens, and for each one waits for it to settle
/// and writes one PNG into that directory, then quits the app.
///
/// Every screen is captured by drawing the app's own window into a bitmap
/// (`NSView.cacheDisplay(in:to:)`) rather than a screen capture — this needs
/// no Screen Recording permission and, unlike `ImageRenderer`, still shows
/// the AppKit/SwiftTerm terminal panes.
@MainActor
enum DemoSnapshots {
    /// Read by `ContentView`'s `PageHost` so the real Subdomains page opens
    /// straight onto a DNS provider tab for one screen. Never touched
    /// outside `run(...)`, so every other launch behaves exactly as before.
    static var subdomainsInitialTab: SubdomainsTab = .sites

    /// Read by `ContentView` so Settings opens straight onto Health for one
    /// screen. Same rule as `subdomainsInitialTab`.
    static var setupInitialSection: SettingsSection = .connection

    /// Read by `CommandPaletteView` so the palette opens already typed into
    /// for one screen. Same rule as `subdomainsInitialTab`.
    static var paletteInitialQuery = ""

    /// Read by `SetupPage.issues` so Connection shows the issue a remedy
    /// answers (no CLI, or setup never ran) for one screen.
    static var settingsIssueRemedy: SettingsIssue.Remedy?
    static var settingsNoMachine = false

    private static let acmeAlias = "acme-devmachine"
    /// A big-display window, the proportions a Mac screenshot has on the
    /// website: at a laptop size the cards and text read oversized.
    private static let defaultWindowSize = NSSize(width: 2000, height: 1120)

    /// `DEVMACHINE_DEMO_WINDOW=1100x700` captures at another size, to check
    /// that a layout stretches with the window.
    static var windowSize: NSSize {
        guard let raw = ProcessInfo.processInfo.environment["DEVMACHINE_DEMO_WINDOW"] else {
            return defaultWindowSize
        }
        return parseWindowSize(raw) ?? defaultWindowSize
    }

    /// The capturing Mac may be set to always show scroll bars; the website
    /// shows the macOS default, where a bar appears only while scrolling.
    static let scrollBarDefaults: [String: Any] = ["AppleShowScrollBars": "WhenScrolling"]

    /// Applied before any window exists, since AppKit reads the scroller
    /// style once when it first lays out a scroll view.
    static func applyScrollBarDefaultsIfNeeded() {
        guard targetDirectory != nil else { return }
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments.merge(scrollBarDefaults) { _, new in new }
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// The menubar's Usage pane is 640pt tall and scrolls; a little taller
    /// here, the screenshot shows the model rows to the end instead of
    /// cutting one in half.
    static let usagePaneHeight: CGFloat = 700

    static func chrome(for screenID: String) -> SnapshotChrome.Kind {
        switch screenID {
        case "pull-requests", "publish-port", "publish-port-via", "menubar-usage", "skeleton-menubar-prs", "skeleton-menubar-usage",
             "worktree-remove", "worktrees-merged", "worktree-foreign",
             "update-toast", "update-toast-large-text", "update-toast-relaunching", "update-toast-installed",
             "file-viewer":
            return .panel
        default:
            return .window
        }
    }

    static func parseWindowSize(_ raw: String) -> NSSize? {
        let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] >= 600, parts[1] >= 400 else { return nil }
        return NSSize(width: parts[0], height: parts[1])
    }

    struct Environment {
        let model: AppModel
        let prStore: PRStore
        let usageStore: HarnessUsageStore
        let caddyStore: CaddyStore
        let settingsStore: SettingsStore
        let wallpaperStore: WallpaperStore
        let harnessSettingsFacade: HarnessSettingsFacade
    }

    /// One screen: its output file name and the steps to reach it. Kept as
    /// data (not a chain of calls) so the sequence can be unit-tested without
    /// touching AppKit.
    struct Screen: Identifiable {
        let id: String
        let fileName: String
        let settleNanoseconds: UInt64
    }

    /// The fixed walk, in capture order. `settleNanoseconds` is how long each
    /// screen waits, after its state change, for layout and the terminal
    /// feed to catch up before the pixels are read.
    static let screens: [Screen] = [
        Screen(id: "sessions", fileName: "01-sessions.png", settleNanoseconds: 900_000_000),
        Screen(id: "session-claude", fileName: "02-session-claude.png", settleNanoseconds: 700_000_000),
        Screen(id: "pull-requests", fileName: "03-pull-requests.png", settleNanoseconds: 400_000_000),
        Screen(id: "subdomains-sites", fileName: "04-subdomains-sites.png", settleNanoseconds: 700_000_000),
        Screen(id: "subdomains-dns-cloudflare", fileName: "05-subdomains-dns-cloudflare.png", settleNanoseconds: 700_000_000),
        Screen(id: "stats", fileName: "06-stats.png", settleNanoseconds: 700_000_000),
        Screen(id: "settings-health", fileName: "07-settings-health.png", settleNanoseconds: 500_000_000),
        Screen(id: "session-defaults", fileName: "08-session-defaults.png", settleNanoseconds: 500_000_000),
        Screen(id: "onboarding", fileName: "09-onboarding.png", settleNanoseconds: 500_000_000),
        Screen(id: "publish-port", fileName: "10-publish-port.png", settleNanoseconds: 400_000_000),
        Screen(id: "operator", fileName: "18-operator.png", settleNanoseconds: 900_000_000),
        Screen(id: "home", fileName: "19-home.png", settleNanoseconds: 700_000_000),
        Screen(id: "menubar-usage", fileName: "20-menubar-usage.png", settleNanoseconds: 400_000_000),
        Screen(id: "command-palette", fileName: "21-command-palette.png", settleNanoseconds: 600_000_000),
        Screen(id: "drop-files", fileName: "22-drop-files.png", settleNanoseconds: 900_000_000),
        Screen(id: "preview", fileName: "23-preview.png", settleNanoseconds: 1_500_000_000),
    ]

    /// The preview screen: acme's dev server session with its landing page
    /// open in a preview tab, and the Preview tab listing what else to open.
    static let previewSession = SessionRef(alias: acmeAlias, name: "web \u{2014} dev server")

    /// The drop screen: a second file dragged over acme's Claude session, whose
    /// prompt already holds the path of the first one, typed by that upload.
    static let dropKind = TerminalKind.remote(
        alias: acmeAlias, session: "claude \u{2014} payments refactor")

    static var droppedPath: String {
        let name = UploadName.make(
            original: "mockup.png",
            date: ISO8601DateFormatter().date(from: "2026-09-30T14:30:12Z") ?? Date(),
            timeZone: TimeZone(identifier: "UTC") ?? .current)
        return "/home/acme/\(ClaudeHarnessAdapter().uploadStoragePolicy.directory)/\(name.fileName)"
    }

    static var dropPrompt: String {
        "look at " + FileUpload.typedText(for: [droppedPath]) + "and match the header"
    }

    static let operatorSelection = SidebarItem.localSession(
        name: Workspace.operatorSession, path: DemoData.operatorPath)

    /// The loading walk (`DEVMACHINE_DEMO_LOADING=1`): every store is held on
    /// its first load, so each screen shows its skeleton. The sidebar comes
    /// first, before the workspace list is seeded.
    static let skeletonScreens: [Screen] = [
        Screen(id: "skeleton-sidebar", fileName: "11-skeleton-home.png", settleNanoseconds: 700_000_000),
        Screen(id: "skeleton-context", fileName: "12-skeleton-context.png", settleNanoseconds: 700_000_000),
        Screen(id: "skeleton-stats", fileName: "13-skeleton-stats.png", settleNanoseconds: 700_000_000),
        Screen(id: "skeleton-subdomains", fileName: "14-skeleton-subdomains.png", settleNanoseconds: 700_000_000),
        Screen(id: "skeleton-dns", fileName: "15-skeleton-dns.png", settleNanoseconds: 700_000_000),
        Screen(id: "skeleton-menubar-prs", fileName: "16-skeleton-menubar-prs.png", settleNanoseconds: 400_000_000),
        Screen(id: "skeleton-menubar-usage", fileName: "17-skeleton-menubar-usage.png", settleNanoseconds: 400_000_000),
    ]

    /// The worktree walk (`DEVMACHINE_DEMO_WALK=worktrees`): the Git tab's
    /// worktree list and both removal sheets, captured on their own so a
    /// check of that feature does not redraw the whole website set.
    static let worktreeScreens: [Screen] = [
        Screen(id: "git-worktrees", fileName: "31-git-worktrees.png", settleNanoseconds: 900_000_000),
        Screen(id: "worktree-remove", fileName: "32-worktree-remove.png", settleNanoseconds: 400_000_000),
        Screen(id: "worktrees-merged", fileName: "33-worktrees-merged.png", settleNanoseconds: 400_000_000),
        Screen(id: "worktree-foreign", fileName: "34-worktree-foreign.png", settleNanoseconds: 400_000_000),
    ]

    /// The harness icon walk (`DEVMACHINE_DEMO_WALK=harness-icons`): acme's
    /// workspace home with Settings → Harnesses → "Show harness icon" on.
    static let harnessIconScreens: [Screen] = [
        Screen(id: "sidebar-harness-icons", fileName: "35-sidebar-harness-icons.png", settleNanoseconds: 900_000_000),
    ]

    /// The update toast walk (`DEVMACHINE_DEMO_WALK=update-toast`): the update
    /// banner above a job card, at the default text size and at the largest.
    static let updateToastScreens: [Screen] = [
        Screen(id: "update-toast", fileName: "36-update-toast.png", settleNanoseconds: 200_000_000),
        Screen(id: "update-toast-large-text", fileName: "37-update-toast-large-text.png", settleNanoseconds: 200_000_000),
        Screen(id: "update-toast-relaunching", fileName: "38-update-toast-relaunching.png", settleNanoseconds: 200_000_000),
        Screen(id: "update-toast-installed", fileName: "39-update-toast-installed.png", settleNanoseconds: 200_000_000),
    ]

    /// The CLI update walk (`DEVMACHINE_DEMO_WALK=cli-update`): the Updates
    /// pane's CLI block before, during and after `update --cli-only`, run on
    /// a fake CLI script.
    static let cliUpdateScreens: [Screen] = [
        Screen(id: "cli-update-available", fileName: "60-cli-update-available.png", settleNanoseconds: 200_000_000),
        Screen(id: "cli-update-running", fileName: "61-cli-update-running.png", settleNanoseconds: 200_000_000),
        Screen(id: "cli-update-updated", fileName: "62-cli-update-updated.png", settleNanoseconds: 200_000_000),
        Screen(id: "cli-update-failed", fileName: "63-cli-update-failed.png", settleNanoseconds: 200_000_000),
        Screen(id: "cli-update-old", fileName: "64-cli-update-old.png", settleNanoseconds: 200_000_000),
    ]

    /// The setup flow walk (`DEVMACHINE_DEMO_WALK=setup-flow`): the first-run
    /// page in each state, then Settings → Connection filled from the CLI and
    /// with each issue the setup button answers.
    static let setupFlowScreens: [Screen] = [
        Screen(id: "setup-start", fileName: "80-setup-start.png", settleNanoseconds: 300_000_000),
        Screen(id: "setup-running", fileName: "81-setup-running.png", settleNanoseconds: 1_200_000_000),
        Screen(id: "setup-failed", fileName: "82-setup-failed.png", settleNanoseconds: 1_200_000_000),
        Screen(id: "setup-agent", fileName: "83-setup-agent.png", settleNanoseconds: 1_200_000_000),
        Screen(id: "setup-agent-stopped", fileName: "84-setup-agent-stopped.png", settleNanoseconds: 1_200_000_000),
        Screen(id: "setup-ready", fileName: "85-setup-ready.png", settleNanoseconds: 300_000_000),
        Screen(id: "settings-connection", fileName: "86-settings-connection.png", settleNanoseconds: 500_000_000),
        Screen(id: "settings-needs-setup", fileName: "87-settings-needs-setup.png", settleNanoseconds: 500_000_000),
        Screen(id: "settings-cli-missing", fileName: "88-settings-cli-missing.png", settleNanoseconds: 500_000_000),
        Screen(id: "settings-no-machine", fileName: "89-settings-no-machine.png", settleNanoseconds: 500_000_000),
    ]

    static let publishViaScreens: [Screen] = [
        Screen(id: "publish-port", fileName: "50-publish-port.png", settleNanoseconds: 400_000_000),
        Screen(id: "publish-port-via", fileName: "51-publish-port-via.png", settleNanoseconds: 400_000_000),
    ]

    /// The machine readiness walk (`DEVMACHINE_DEMO_WALK=machine-ready`): a
    /// machine without devmachine-app on Home and in the sidebar, Prepare
    /// running, failed and done on fake scripts, the old-CLI and outdated
    /// cards, a workspace with no SSH alias, and onboarding's Install CLI.
    static let machineReadyScreens: [Screen] = [
        Screen(id: "ready-home", fileName: "70-ready-home.png", settleNanoseconds: 700_000_000),
        Screen(id: "ready-running", fileName: "71-ready-running.png", settleNanoseconds: 1_500_000_000),
        Screen(id: "ready-failed", fileName: "72-ready-failed.png", settleNanoseconds: 500_000_000),
        Screen(id: "ready-done", fileName: "73-ready-done.png", settleNanoseconds: 500_000_000),
        Screen(id: "ready-old-cli", fileName: "74-ready-old-cli.png", settleNanoseconds: 300_000_000),
        Screen(id: "ready-outdated", fileName: "75-ready-outdated.png", settleNanoseconds: 300_000_000),
        Screen(id: "install-cli", fileName: "76-install-cli.png", settleNanoseconds: 300_000_000),
        Screen(id: "install-cli-running", fileName: "77-install-cli-running.png", settleNanoseconds: 1_200_000_000),
        Screen(id: "install-cli-failed", fileName: "78-install-cli-failed.png", settleNanoseconds: 300_000_000),
    ]

    /// The DNS setup walk (`DEVMACHINE_DEMO_WALK=dns-setup`): see `DemoDNSWalk`.
    static let dnsSetupScreens: [Screen] = [
        Screen(id: "dns-none", fileName: "80-dns-none.png", settleNanoseconds: 500_000_000),
        Screen(id: "dns-not-synced", fileName: "81-dns-not-synced.png", settleNanoseconds: 500_000_000),
        Screen(id: "dns-no-zones", fileName: "82-dns-no-zones.png", settleNanoseconds: 500_000_000),
        Screen(id: "dns-syncing", fileName: "83-dns-syncing.png", settleNanoseconds: 700_000_000),
        Screen(id: "dns-failed", fileName: "84-dns-failed.png", settleNanoseconds: 500_000_000),
        Screen(id: "dns-ready", fileName: "85-dns-ready.png", settleNanoseconds: 700_000_000),
    ]

    /// The file viewer walk (`DEVMACHINE_DEMO_WALK=file-viewer`): a Swift file
    /// in the viewer, highlighted. It is also the check that a packaged app
    /// finds the highlighter's script inside its own bundle.
    static let fileViewerScreens: [Screen] = [
        Screen(id: "file-viewer", fileName: "40-file-viewer.png", settleNanoseconds: 200_000_000),
    ]

    /// The browser walk (`DEVMACHINE_DEMO_WALK=preview-browser`): see
    /// `DemoPreviewBrowserCheck`. Its screen is the page after every check.
    static let previewBrowserScreens: [Screen] = [
        Screen(id: "preview-browser", fileName: "41-preview-browser.png", settleNanoseconds: 500_000_000),
    ]

    static let fileViewerPath = "/home/acme/dash/Sources/Greeter.swift"

    static let fileViewerCode = """
        import Foundation

        struct Greeter {
            let name: String

            func greet() -> String {
                "Hello, \\(name)"
            }
        }

        """

    /// The file transfer walk (`DEVMACHINE_DEMO_WALK=file-transfer`): the
    /// Files tab with a folder receiving a drop, and the result cards.
    static let fileTransferScreens: [Screen] = [
        Screen(id: "file-transfer-tree", fileName: "50-file-transfer-tree.png", settleNanoseconds: 200_000_000),
        Screen(id: "file-transfer-saved", fileName: "51-file-transfer-saved.png", settleNanoseconds: 200_000_000),
        Screen(id: "file-transfer-failed", fileName: "52-file-transfer-failed.png", settleNanoseconds: 200_000_000),
    ]

    /// The sizing walk (`DEVMACHINE_DEMO_WALK=sizing`): the screens a text
    /// size change touches most, run once per `DEVMACHINE_DEMO_UI_SCALE`.
    static let sizingScreens: [Screen] = [
        Screen(id: "sessions", fileName: "40-sidebar.png", settleNanoseconds: 900_000_000),
        Screen(id: "session-claude", fileName: "41-context-panel.png", settleNanoseconds: 700_000_000),
        Screen(id: "session-defaults", fileName: "42-settings-harnesses.png", settleNanoseconds: 500_000_000),
        Screen(id: "subdomains-sites", fileName: "43-subdomains.png", settleNanoseconds: 700_000_000),
        Screen(id: "stats", fileName: "44-stats.png", settleNanoseconds: 700_000_000),
        Screen(id: "update-toast", fileName: "45-update-toast.png", settleNanoseconds: 200_000_000),
        Screen(id: "publish-port", fileName: "46-add-subdomain.png", settleNanoseconds: 400_000_000),
        Screen(id: "command-palette", fileName: "47-command-palette.png", settleNanoseconds: 600_000_000),
    ]

    /// `DEVMACHINE_DEMO_UI_SCALE=1.6` captures a walk at that text size.
    static func uiScale(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Double? {
        guard let raw = environment["DEVMACHINE_DEMO_UI_SCALE"], let value = Double(raw) else { return nil }
        return Appearance.clampUIFontScale(value)
    }

    static func walk(environment: [String: String] = ProcessInfo.processInfo.environment) -> [Screen] {
        if DemoMode.holdsLoading { return skeletonScreens }
        switch environment["DEVMACHINE_DEMO_WALK"] {
        case "worktrees": return worktreeScreens
        case "harness-icons": return harnessIconScreens
        case "update-toast": return updateToastScreens
        case "cli-update": return cliUpdateScreens
        case "file-viewer": return fileViewerScreens
        case "file-transfer": return fileTransferScreens
        case "sizing": return sizingScreens
        case "preview-browser": return previewBrowserScreens
        case "machine-ready": return machineReadyScreens
        case "publish-via": return publishViaScreens
        case "setup-flow": return setupFlowScreens
        case "dns-setup": return dnsSetupScreens
        #if DEBUG
        case "machines": return DemoAddMachine.screens
        #endif
        default: return screens
        }
    }

    /// `DEVMACHINE_DEMO_HIDDEN=1` draws every window fully transparent and
    /// never brings the app forward: the capture reads the views, not the
    /// screen, so nothing needs to show on the Mac running it.
    static var isHidden: Bool {
        ProcessInfo.processInfo.environment["DEVMACHINE_DEMO_HIDDEN"] == "1"
    }

    /// The snapshot directory from the environment, or nil when this is a
    /// normal demo launch with nothing to capture.
    static var targetDirectory: URL? {
        guard DemoMode.isActive,
              let path = ProcessInfo.processInfo.environment["DEVMACHINE_DEMO_SNAPSHOTS"],
              !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func runIfNeeded(_ environment: Environment) {
        guard let directory = targetDirectory else { return }
        Task { @MainActor in
            await run(into: directory, environment: environment)
            NSApp.terminate(nil)
        }
    }

    private static func run(into directory: URL, environment: Environment) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment.model.checkCLIAndProceed(isConfigured: true)
        environment.model.sidebarCollapsed = false
        environment.model.contextCollapsed = false
        // A translucent terminal (`TerminalPaneView.applyAppearance`, which
        // reads `SettingsStore.shared` directly) lets the wallpaper bleed
        // through a little where it has painted — full opacity reads
        // crisper for a screenshot than that ambient wash.
        var settings = environment.settingsStore.settings ?? .empty
        settings.terminalOpacity = 1
        if let scale = uiScale() { settings.uiFontScale = scale }
        environment.settingsStore.settings = settings
        environment.model.settings = settings

        guard let window = await mainWindow() else { return }
        window.setContentSize(windowSize)
        window.center()
        if isHidden {
            window.alphaValue = 0
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        for screen in walk() {
            await prepare(screen, environment: environment, mainWindow: window)
            try? await Task.sleep(nanoseconds: screen.settleNanoseconds)
            // A pane resized after its transcript was drawn (the grid, the
            // context panel opening) can be left blank or scrolled past its
            // first lines; drawing it again right before the capture fixes both.
            TerminalRegistry.shared.replayDemoTranscripts()
            try? await Task.sleep(nanoseconds: 250_000_000)
            let view: NSView
            switch screen.id {
            case "pull-requests", "skeleton-menubar-prs":
                view = standaloneView(
                    prPanel(environment), fittingSize: NSSize(width: 480, height: 640), fixedHeight: 640)
            case "menubar-usage", "skeleton-menubar-usage":
                view = standaloneView(
                    prPanel(environment, tab: .usage, height: usagePaneHeight),
                    fittingSize: NSSize(width: 780, height: usagePaneHeight), fixedHeight: usagePaneHeight)
            case "onboarding":
                view = standaloneView(onboardingPage("onboarding", environment), fittingSize: windowSize, autosize: false)
                // `OnboardingPage` reads its demo flow from its own `.task`,
                // which only starts once SwiftUI's next run loop turn — the
                // window is already laid out by here, but the view's first
                // render still shows its `@State` initial value otherwise.
                try? await Task.sleep(nanoseconds: 300_000_000)
            case "setup-start", "setup-running", "setup-failed", "setup-agent", "setup-agent-stopped", "setup-ready":
                view = standaloneView(
                    onboardingPage(screen.id, environment), fittingSize: NSSize(width: 1400, height: 860),
                    autosize: false)
                try? await Task.sleep(nanoseconds: 900_000_000)
                TerminalRegistry.shared.replayDemoTranscripts()
                try? await Task.sleep(nanoseconds: 250_000_000)
            case "publish-port":
                view = standaloneView(publishSheet(environment), fittingSize: NSSize(width: 480, height: 620))
            case "publish-port-via":
                view = standaloneView(
                    publishSheet(environment, workspace: "umbrella"), fittingSize: NSSize(width: 480, height: 700))
            case "worktree-remove":
                view = standaloneView(worktreeRemovalSheet, fittingSize: NSSize(width: 460, height: 400))
            case "worktrees-merged":
                view = standaloneView(mergedWorktreesSheet, fittingSize: NSSize(width: 420, height: 360))
            case "worktree-foreign":
                view = standaloneView(foreignWorktreeSheet, fittingSize: NSSize(width: 460, height: 560))
            case "file-viewer":
                view = await fileViewerView(model: environment.model)
            case "file-transfer-tree":
                view = await fileTransferTree(model: environment.model)
            case "file-transfer-saved", "file-transfer-failed":
                view = fileTransferNotice(failed: screen.id == "file-transfer-failed")
            #if DEBUG
            case "update-toast", "update-toast-large-text", "update-toast-relaunching", "update-toast-installed":
                view = await updateToastView(screen.id, model: environment.model)
            case "cli-update-available", "cli-update-running", "cli-update-updated", "cli-update-failed",
                 "cli-update-old":
                view = await cliUpdateView(screen.id)
            case "ready-old-cli", "ready-outdated":
                view = readinessCardView(screen.id, model: environment.model)
            case "install-cli", "install-cli-running", "install-cli-failed":
                view = await installCLIView(screen.id, environment: environment)
            #endif
            default:
                window.displayIfNeeded()
                view = window.contentView ?? NSView()
            }
            capture(view, kind: chrome(for: screen.id), to: directory.appendingPathComponent(screen.fileName))
        }

        environment.model.showCommandPalette = false
        PaneUploadStore.shared.dropTarget = nil
        DemoData.typedAtPrompt = [:]
        PreviewStore.shared.closeAll()
        #if DEBUG
        DemoDNSWalk.reset()
        #endif
        environment.model.goHome()
    }

    /// Drives the real window/model to the state each screen needs. The
    /// three screens with no natural place in the main window (the menubar's
    /// pull-request popover, first-run onboarding, and the quick-publish
    /// sheet) are rendered in their own offscreen window instead, right
    /// where they are captured (see `run`).
    private static func prepare(_ screen: Screen, environment: Environment, mainWindow: NSWindow) async {
        let model = environment.model
        // `goHome()` tears down whatever page is up; a beat later, so SwiftUI
        // actually renders that empty state, `SetupPage`/`SubdomainsView` are
        // freshly created next — the only time their `initial…` parameter
        // (read from a static var, since `PageHost` builds them with no
        // arguments) has any effect. Skipping the beat leaves the *previous*
        // instance on screen, still on its own tab.
        model.showCommandPalette = false
        PaneUploadStore.shared.dropTarget = nil
        DemoData.typedAtPrompt = [:]
        PreviewStore.shared.closeAll()
        settingsIssueRemedy = nil
        settingsNoMachine = false
        model.goHome()
        try? await Task.sleep(nanoseconds: 150_000_000)
        #if DEBUG
        if DemoAddMachine.handles(screen.id) {
            await DemoAddMachine.prepare(screen.id, model: model)
            return
        }
        #endif
        switch screen.id {
        case "sessions":
            model.stackWorkspace(acmeAlias)
        case "sidebar-harness-icons":
            environment.settingsStore.settings?.showsHarnessIcons = true
            model.stackWorkspace(acmeAlias)
        case "session-claude":
            // A different workspace/session than the "sessions" grid, not
            // just a different screen: `TerminalRegistry` caches one pane per
            // (workspace, session) and only sizes it once, the first time it
            // is mounted — reusing "sessions"'s own claude pane here would
            // maximize it still carrying the grid cell's small cached size.
            model.clickSession(SessionRef(alias: "globex-devmachine", name: "claude"))
            model.contextTab = .context
        case "operator":
            model.clickLocalSession(operatorSelection)
            model.contextTab = .context
        case "subdomains-sites":
            subdomainsInitialTab = .sites
            model.showPage(.subdomains)
        case "subdomains-dns-cloudflare":
            subdomainsInitialTab = .provider("cloudflare")
            model.showPage(.subdomains)
        case "stats":
            model.showPage(.stats)
        case "settings-health":
            setupInitialSection = .advanced
            model.showPage(.setup)
        case "session-defaults":
            setupInitialSection = .harnesses
            model.showPage(.setup)
        #if DEBUG
        case "settings-connection", "settings-needs-setup", "settings-cli-missing", "settings-no-machine":
            settingsIssueRemedy = screen.id == "settings-needs-setup"
                ? .runSetup : (screen.id == "settings-cli-missing" ? .installCLI : nil)
            settingsNoMachine = screen.id == "settings-no-machine"
            model.seedDemoDetected(CLIDetectedSettings(
                opsRepoPath: DemoData.operatorPath, adminMachine: "main",
                publicIP: DemoData.machineAddress, baseDomain: "example.com"))
            setupInitialSection = .connection
            model.showPage(.setup)
        #endif
        case "git-worktrees":
            guard case let .remote(alias, session) = dropKind else { break }
            model.clickSession(SessionRef(alias: alias, name: session))
            model.contextTab = .git
        case "command-palette":
            paletteInitialQuery = "sub"
            model.showCommandPalette = true
        case "drop-files":
            guard case let .remote(alias, session) = dropKind else { break }
            model.clickSession(SessionRef(alias: alias, name: session))
            model.contextTab = .context
            DemoData.typedAtPrompt = [dropKind: dropPrompt]
            PaneUploadStore.shared.dropTarget = dropKind
        #if DEBUG
        case "dns-none", "dns-not-synced", "dns-no-zones", "dns-syncing", "dns-failed", "dns-ready":
            await DemoDNSWalk.prepare(screen.id, store: environment.caddyStore, model: model)
        case "ready-home":
            DemoMachineReady.seed(MachineReadinessStore.shared, model: model)
        case "ready-running":
            DemoMachineReady.seed(MachineReadinessStore.shared, model: model, script: .prepareSlow)
            Task { await MachineReadinessStore.shared.prepare(DemoMachineReady.machine) }
        case "ready-failed":
            DemoMachineReady.seed(MachineReadinessStore.shared, model: model, script: .prepareFails)
            await MachineReadinessStore.shared.prepare(DemoMachineReady.machine)
        case "ready-done":
            DemoMachineReady.seed(MachineReadinessStore.shared, model: model, script: .prepareSucceeds)
            await MachineReadinessStore.shared.prepare(DemoMachineReady.machine)
        case "preview-browser":
            if let directory = targetDirectory {
                await DemoPreviewBrowserCheck.run(
                    window: mainWindow, directory: directory, session: previewSession, model: model)
            }
        #endif
        case "preview":
            model.clickSession(previewSession)
            model.contextTab = .preview
            PreviewStore.shared.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        case "skeleton-context":
            model.seedDemoWorkspacesAwaitingSessions(answered: "globex-devmachine")
            model.clickSession(SessionRef(alias: "globex-devmachine", name: "claude"))
            model.contextTab = .context
        case "skeleton-stats":
            model.showPage(.stats)
        case "skeleton-subdomains":
            subdomainsInitialTab = .sites
            model.showPage(.subdomains)
        case "skeleton-dns":
            subdomainsInitialTab = .provider("cloudflare")
            model.showPage(.subdomains)
        default:
            break
        }
    }

    // MARK: - Standalone screens

    private static func prPanel(
        _ environment: Environment, tab: MenuBarTab = .pullRequests, height: CGFloat? = nil
    ) -> some View {
        MenuBarPanel(initialTab: tab, height: height)
            .environmentObject(environment.prStore)
            .environmentObject(environment.usageStore)
            .environmentObject(environment.model)
            .environment(\.harnessSettingsFacade, environment.harnessSettingsFacade)
    }

    private static func onboardingPage(_ id: String, _ environment: Environment) -> some View {
        let state = DemoSetupFlow.state(for: id)
        return OnboardingPage(demoFlow: state?.flow, demoPaneKind: state?.pane)
            .environmentObject(environment.wallpaperStore)
    }

    private static func publishSheet(_ environment: Environment, workspace: String? = nil) -> some View {
        var settings = AppSettings.empty
        settings.baseDomain = "example.com"
        let workspace = workspace ?? DemoData.workspaces.first?.name ?? ""
        return AddSubdomainSheet(
            settings: settings,
            workspaces: DemoData.workspaces,
            preselectedWorkspace: workspace,
            suggestedPorts: DemoData.publishSuggestions.ports,
            suggestedLabel: workspace)
            .environmentObject(environment.caddyStore)
    }

    private static var worktreeRemovalSheet: some View {
        let check = DemoData.worktreeChecks.first { $0.path.hasSuffix("api-webhooks") }
        let worktree = DemoData.gitSnapshot.worktrees.first { $0.path == check?.path }
            ?? DemoData.gitSnapshot.worktrees[0]
        return WorktreeRemovalSheet(
            request: WorktreeRemovalRequest(worktree: worktree, check: check, phase: .ready),
            onRemove: { _ in }, onRemoveAsAdmin: { _ in }, onPrune: {}, onDeleteLeftover: {}, onCancel: {})
            .background(Color.dmSidebarBg)
    }

    private static var foreignWorktreeSheet: some View {
        let check = DemoData.foreignWorktreeCheck
        let worktree = GitSnapshot.Worktree(path: check.path, head: "4d5e6f7a", branch: check.branch, isMain: false)
        var request = WorktreeRemovalRequest(worktree: worktree, check: check, phase: .ready)
        request.route = .admin(machine: "main")
        request.mainWorktree = "/home/acme/dev/api"
        return WorktreeRemovalSheet(
            request: request,
            onRemove: { _ in }, onRemoveAsAdmin: { _ in }, onPrune: {}, onDeleteLeftover: {}, onCancel: {})
            .background(Color.dmSidebarBg)
    }

    private static var mergedWorktreesSheet: some View {
        MergedWorktreesRemovalSheet(
            request: MergedRemovalRequest(checks: DemoData.worktreeChecks.filter(\.isCleanAndMerged)),
            onRemove: { _ in }, onCancel: {})
            .background(Color.dmSidebarBg)
    }

    /// Every store here answers from silence, so the tree never reaches a host.
    private static func fileTransferTree(model: AppModel) async -> NSView {
        let silent = HostRunner(remote: RemoteService(runner: DemoFileRunner(stdout: "")), local: DemoMode.runner)
        let root = "/home/acme/dash"
        let target = CommandTarget.remote(alias: acmeAlias, session: "dash")
        let store = FileTreeStore(host: silent)
        store.start(target)
        for _ in 0..<50 where store.isLoading {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        store.root = root
        store.children = [
            root: [
                FileTreeEntry(name: "assets", kind: .directory),
                FileTreeEntry(name: "Sources", kind: .directory),
                FileTreeEntry(name: "README.md", kind: .file),
                FileTreeEntry(name: "relatório final.pdf", kind: .file),
            ],
            root + "/assets": [FileTreeEntry(name: "logo.png", kind: .file)],
        ]
        store.expanded = [root + "/assets"]
        store.selected = root + "/relatório final.pdf"
        let transfers = FileTransferStore(cli: { throw DevmachineCLIError.commandFailed("demo") })
        transfers.busy = [root + "/assets"]
        let tab = FilesTab(store: store, target: target, workspace: "acme", transfers: transfers)
            .environmentObject(model)
            .environmentObject(FileViewerStore(host: silent))
            .environmentObject(FileSearchStore(host: silent))
            .environmentObject(FilesStore(service: FileService(host: silent), runner: DemoFileRunner(stdout: "")))
            .background(Color.dmSidebarBg)
        return standaloneView(tab, fittingSize: NSSize(width: 300, height: 260), autosize: false)
    }

    private static func fileTransferNotice(failed: Bool) -> NSView {
        let notice = failed
            ? TransferNotice(
                title: "Saved 1 of 2 to ~/Downloads",
                detail: "/home/acme/dash/secret.env cannot be read", reveal: nil, failed: true)
            : TransferNotice(
                title: "Saved to ~/Downloads/relatório final.pdf", detail: nil,
                reveal: URL(fileURLWithPath: "/tmp/relatório final.pdf"), failed: false)
        return standaloneView(
            TransferNoticeCard(notice: notice, reveal: notice.reveal.map { _ in {} }, close: {})
                .padding(18),
            fittingSize: NSSize(width: 320, height: 200))
    }

    private static func fileViewerView(model: AppModel) async -> NSView {
        let data = Data(fileViewerCode.utf8)
        let runner = DemoFileRunner(stdout: "\(data.count)\u{1e}" + data.base64EncodedString())
        let store = FileViewerStore(
            host: HostRunner(remote: RemoteService(runner: runner), local: DemoMode.runner))
        store.open(.remote(alias: acmeAlias, session: "dash"), path: fileViewerPath)
        for _ in 0..<50 where store.preview == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let view = standaloneView(
            FileViewerView().environmentObject(store).environmentObject(model),
            fittingSize: NSSize(width: 620, height: 360), autosize: false)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        return view
    }

    #if DEBUG
    private static func updateToastView(_ id: String, model: AppModel) async -> NSView {
        let saved = DMFont.scale
        defer { DMFont.scale = saved }
        DMFont.scale = id == "update-toast" ? uiScale() ?? 1 : Appearance.uiFontScaleRange.upperBound
        let state: DemoUpdateToasts.State
        switch id {
        case "update-toast-relaunching": state = .relaunching
        case "update-toast-installed": state = .installed
        default: state = .available
        }
        return standaloneView(
            await DemoUpdateToasts.toastStack(state, model: model), fittingSize: NSSize(width: 400, height: 300))
    }

    private static func readinessCardView(_ id: String, model: AppModel) -> NSView {
        let store = MachineReadinessStore.shared
        let outdated = id == "ready-outdated"
        DemoMachineReady.seed(store, model: model, cliVersion: outdated ? "0.7.24" : "0.7.23", outdated: outdated)
        return standaloneView(
            DemoMachineReady.card(store, model: model, machine: outdated ? "backup" : DemoMachineReady.machine),
            fittingSize: NSSize(width: 568, height: 400))
    }

    private static func installCLIView(_ id: String, environment: Environment) async -> NSView {
        let view = standaloneView(
            onboardingPage(id, environment), fittingSize: NSSize(width: 1100, height: 760), autosize: false)
        try? await Task.sleep(nanoseconds: 300_000_000)
        return view
    }

    private static func cliUpdateView(_ id: String) async -> NSView {
        let state: DemoCLIUpdate.State
        switch id {
        case "cli-update-running": state = .running
        case "cli-update-updated": state = .updated
        case "cli-update-failed": state = .failed
        case "cli-update-old": state = .oldCLI
        default: state = .available
        }
        return standaloneView(await DemoCLIUpdate.pane(state), fittingSize: NSSize(width: 688, height: 700))
    }
    #endif

    // MARK: - AppKit plumbing

    private static func mainWindow() async -> NSWindow? {
        for _ in 0..<50 {
            if let window = NSApp.windows.first(where: { $0.title == "Devmachine" }) {
                return window
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return NSApp.windows.first
    }

    /// Hosts one SwiftUI view in its own borderless window, sized to fit the
    /// view's own content, so a compact popover or sheet is not captured
    /// inside a mostly-empty full-size window. `fixedHeight`, set for the
    /// menubar's own panel, keeps its real (self-sizing, screen-width-based)
    /// width but ignores its *height* fit: a scrollable, unbounded-height
    /// list reports a `fittingSize` far taller than the panel's own fixed
    /// `.frame(height:)`.
    private static func standaloneView<V: View>(
        _ view: V, fittingSize: NSSize, autosize: Bool = true, fixedHeight: CGFloat? = nil
    ) -> NSView {
        let hosting = NSHostingView(rootView: view.environment(\.dmMetrics, .current))
        // A full-window page fills whatever it is given; left to size the
        // window to its content, it grew thousands of points tall.
        if !autosize { hosting.sizingOptions = [] }
        hosting.frame = NSRect(origin: .zero, size: fittingSize)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        if isHidden { window.alphaValue = 0 }
        window.setIsVisible(true)
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        if autosize {
            let fitted = hosting.fittingSize
            let size = NSSize(
                width: fitted.width > 0 ? fitted.width : fittingSize.width,
                height: fixedHeight ?? (fitted.height > 0 ? fitted.height : fittingSize.height))
            hosting.setFrameSize(size)
            window.setContentSize(size)
        }
        window.displayIfNeeded()
        return hosting
    }

    private static func capture(_ view: NSView, kind: SnapshotChrome.Kind, to url: URL) {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let framed = SnapshotChrome.framed(flattenTransparency(rep), scale: scale, kind: kind)
        guard let data = framed.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    /// SwiftTerm draws each terminal row as its own layer, only once that row
    /// has actually shown a character; a row a transcript never reaches (a
    /// tall pane, a short transcript) has no layer at all yet, so
    /// `cacheDisplay` — a plain bitmap capture, not the window server's own
    /// compositor — leaves it fully transparent rather than painted in the
    /// terminal's own background. Flattening onto the app's own background
    /// color turns that gap into the plain dark it reads as on screen,
    /// instead of the bitmap's transparent default (white once saved as an
    /// opaque PNG and viewed).
    private static func flattenTransparency(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
        let background = NSColor(srgbRed: 0x0E / 255, green: 0x12 / 255, blue: 0x17 / 255, alpha: 1)
        let size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        guard let flattened = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: flattened)
        else { return rep }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return flattened
    }
}

private struct DemoFileRunner: CommandRunner {
    let stdout: String

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        (stdout, "", 0)
    }
}
