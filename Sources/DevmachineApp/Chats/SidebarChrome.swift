import SwiftUI
import DevmachineCore

/// Shows or hides the sidebar, in the title bar band on the window
/// buttons' line: at the sidebar's right edge while it is open, right after
/// the window buttons while it is closed.
struct SidebarToggleButton: View {
    @EnvironmentObject private var model: AppModel

    static func label(collapsed: Bool) -> String { collapsed ? "Show sidebar" : "Hide sidebar" }

    var body: some View {
        DMIconButton(systemImage: "sidebar.left", size: 13, hitSize: CGSize(width: 24, height: 24)) {
            withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed.toggle() }
        }
        .dmHelp(Self.label(collapsed: model.sidebarCollapsed) + " (⌘B)")
        .accessibilityLabel(Self.label(collapsed: model.sidebarCollapsed))
        .demoClickTarget("footer:close-sidebar")
    }
}

/// Where the toggle's center goes, in points from the window's top left.
enum SidebarTogglePlacement {
    static let hit: CGFloat = 24
    static let gapAfterButtons: CGFloat = 14
    static let rightPadding: CGFloat = 12

    static func center(collapsed: Bool, sidebarWidth: CGFloat, buttons: CGRect) -> CGPoint {
        let x = collapsed
            ? buttons.maxX + gapAfterButtons + hit / 2
            : sidebarWidth - rightPadding - hit / 2
        return CGPoint(x: x, y: buttons.midY)
    }
}

/// The window's close, minimise and zoom buttons, in points from the top
/// left of the window, read where macOS put them (the toolbar moves them).
/// It also keeps the title bar see-through, so each mode's own surface runs
/// up under it.
struct WindowButtonsReader: NSViewRepresentable {
    @Binding var frame: CGRect

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = { frame = $0 }
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = { frame = $0 }
    }

    final class ReaderView: NSView {
        var onChange: (CGRect) -> Void = { _ in }
        private var last: CGRect = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowChanged), name: name, object: window)
            }
            for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(fullScreenWillChange(_:)), name: name, object: window)
            }
            window.toolbar?.isVisible = !window.styleMask.contains(.fullScreen)
            windowChanged()
        }

        override func layout() {
            super.layout()
            windowChanged()
        }

        /// Full screen hides the toolbar: macOS keeps a visible toolbar on
        /// screen there as an opaque band that pushes every column down. The
        /// window buttons still slide in with the menu bar without it.
        @objc private func fullScreenWillChange(_ notification: Notification) {
            window?.toolbar?.isVisible = notification.name == NSWindow.willExitFullScreenNotification
        }

        @objc private func windowChanged() {
            guard let window, let frameView = window.contentView?.superview else { return }
            // In full screen the buttons live in the title bar's own window, so
            // converting them to this one gives a point far down the screen.
            // The layout keeps the windowed place instead.
            if window.styleMask.contains(.fullScreen) {
                report(last == .zero ? SidebarHeaderSpacing.fallbackButtons : last)
                return
            }
            let rects = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { type -> CGRect? in
                guard let button = window.standardWindowButton(type), !button.isHidden else { return nil }
                let rect = button.convert(button.bounds, to: frameView)
                let top = frameView.isFlipped ? rect.minY : frameView.bounds.height - rect.maxY
                return CGRect(x: rect.minX, y: top, width: rect.width, height: rect.height)
            }
            guard let first = rects.first else { return }
            report(rects.dropFirst().reduce(first) { $0.union($1) })
        }

        private func report(_ union: CGRect) {
            guard union != last else { return }
            last = union
            DispatchQueue.main.async { [onChange] in onChange(union) }
        }
    }
}

private struct SidebarHeaderTopKey: EnvironmentKey {
    static let defaultValue: CGFloat = SidebarHeaderSpacing.fallback
}

private struct TitleLineKey: EnvironmentKey {
    static let defaultValue: CGFloat = SidebarHeaderSpacing.fallbackLine
}

extension EnvironmentValues {
    /// The window buttons' vertical center, in points from the window's top:
    /// the line the title bar's controls sit on.
    var titleLine: CGFloat {
        get { self[TitleLineKey.self] }
        set { self[TitleLineKey.self] = newValue }
    }

    /// Where the sidebar's header starts, in points from the window's top:
    /// close under the window buttons. The sidebars run under the title bar.
    var sidebarHeaderTop: CGFloat {
        get { self[SidebarHeaderTopKey.self] }
        set { self[SidebarHeaderTopKey.self] = newValue }
    }
}

/// The sidebar's top block (title, then the New row) keeps the same space
/// above it, under the window buttons, as below it, before the list.
enum SidebarHeaderSpacing {
    /// Under the New row, before the list.
    static let blockGap: CGFloat = 14
    /// The list's first group header has more room above its text than the
    /// title row has; this evens the two, so the gaps read the same.
    static let textAlignment: CGFloat = 9.5
    static let fallback: CGFloat = 52
    static let fallbackLine: CGFloat = 22
    /// The window buttons' place when there is none to read (a window that
    /// opens in full screen), matching the fallbacks above.
    static let fallbackButtons = CGRect(x: 20, y: fallbackLine - 7, width: 52, height: 14)

    static func line(buttons: CGRect) -> CGFloat {
        buttons == .zero ? fallbackLine : buttons.midY
    }

    static func top(buttons: CGRect) -> CGFloat {
        buttons == .zero ? fallback : buttons.maxY + blockGap + textAlignment
    }
}

struct SidebarHeaderTop: ViewModifier {
    @Environment(\.sidebarHeaderTop) private var top

    func body(content: Content) -> some View {
        content.padding(.top, top)
    }
}

/// A sidebar column drawn from the window's top edge, under the window
/// buttons, with its header placed by `SidebarHeaderTop`.
struct SidebarUnderTitlebar: ViewModifier {
    func body(content: Content) -> some View {
        content.ignoresSafeArea(edges: .top)
    }
}
