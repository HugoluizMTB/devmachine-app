import SwiftUI
import AppKit
import DevmachineCore

/// Gives the main window a large first size (`MainWindowSizing`) when AppKit
/// has no saved frame for it. SwiftUI otherwise sized it to its first
/// content, the setup page, and saved that small frame for every later launch.
struct MainWindowSizer: NSViewRepresentable {
    static let autosaveKey = "NSWindow Frame main"

    /// Read in `DevmachineApp.init`, before any window exists, so a frame
    /// SwiftUI writes while opening the window never counts as a saved one.
    @MainActor static var savedFrameAtLaunch: String?
    @MainActor private static var applied = false

    @MainActor static func readSavedFrame(from defaults: UserDefaults = .standard) {
        savedFrameAtLaunch = defaults.string(forKey: autosaveKey)
    }

    func makeNSView(context: Context) -> NSView {
        SizerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SizerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !MainWindowSizer.applied, !DemoMode.isActive else { return }
            MainWindowSizer.applied = true
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame,
                  let frame = MainWindowSizing.initialFrame(
                    savedFrame: MainWindowSizer.savedFrameAtLaunch, visible: visible)
            else { return }
            DispatchQueue.main.async { window.setFrame(frame, display: true) }
        }
    }
}
