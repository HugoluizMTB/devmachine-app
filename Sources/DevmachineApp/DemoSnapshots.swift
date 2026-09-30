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

    private static let acmeAlias = "acme-devmachine"
    private static let windowSize = NSSize(width: 1440, height: 900)

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
    ]

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
        environment.settingsStore.settings = settings
        environment.model.settings = settings

        guard let window = await mainWindow() else { return }
        window.setContentSize(windowSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        for screen in screens {
            await prepare(screen, environment: environment, mainWindow: window)
            try? await Task.sleep(nanoseconds: screen.settleNanoseconds)
            let view: NSView
            switch screen.id {
            case "pull-requests":
                view = standaloneView(
                    prPanel(environment), fittingSize: NSSize(width: 480, height: 640), fixedHeight: 640)
            case "onboarding":
                view = standaloneView(onboardingPage(environment), fittingSize: windowSize)
                // `OnboardingPage` reads `demoDetection` from its own `.task`,
                // which only starts once SwiftUI's next run loop turn — the
                // window is already laid out by here, but the view's first
                // render still shows its `@State` initial value otherwise.
                try? await Task.sleep(nanoseconds: 300_000_000)
            case "publish-port":
                view = standaloneView(publishSheet(environment), fittingSize: NSSize(width: 480, height: 620))
            default:
                window.displayIfNeeded()
                view = window.contentView ?? NSView()
            }
            capture(view, to: directory.appendingPathComponent(screen.fileName))
        }

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
        model.goHome()
        try? await Task.sleep(nanoseconds: 150_000_000)
        switch screen.id {
        case "sessions":
            model.stackWorkspace(acmeAlias)
        case "session-claude":
            // A different workspace/session than the "sessions" grid, not
            // just a different screen: `TerminalRegistry` caches one pane per
            // (workspace, session) and only sizes it once, the first time it
            // is mounted — reusing "sessions"'s own claude pane here would
            // maximize it still carrying the grid cell's small cached size.
            model.clickSession(SessionRef(alias: "globex-devmachine", name: "claude"))
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
        default:
            break
        }
    }

    // MARK: - Standalone screens

    private static func prPanel(_ environment: Environment) -> some View {
        MenuBarPanel()
            .environmentObject(environment.prStore)
            .environmentObject(environment.usageStore)
            .environmentObject(environment.model)
            .environment(\.harnessSettingsFacade, environment.harnessSettingsFacade)
    }

    private static func onboardingPage(_ environment: Environment) -> some View {
        OnboardingPage(demoDetection: OnboardingDetection(
            homebrewFound: true,
            cliFound: false,
            adminMachine: nil,
            missingPackageMachines: [],
            agents: [
                DetectedAgent(kind: .claude, executablePath: "/opt/homebrew/bin/claude"),
                DetectedAgent(kind: .codex, executablePath: "/opt/homebrew/bin/codex"),
            ]))
            .environmentObject(environment.wallpaperStore)
    }

    private static func publishSheet(_ environment: Environment) -> some View {
        var settings = AppSettings.empty
        settings.baseDomain = "example.com"
        return AddSubdomainSheet(
            settings: settings,
            workspaces: DemoData.workspaces,
            preselectedWorkspace: DemoData.workspaces.first?.name,
            suggestedPorts: DemoData.publishSuggestions.ports,
            suggestedLabel: DemoData.workspaces.first?.name ?? "")
            .environmentObject(environment.caddyStore)
    }

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
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: fittingSize)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
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

    private static func capture(_ view: NSView, to url: URL) {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let flattened = flattenTransparency(rep)
        guard let data = flattened.representation(using: .png, properties: [:]) else { return }
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
