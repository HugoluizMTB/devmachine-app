import SwiftUI
import AppKit
import SwiftTerm
import DevmachineCore

enum TerminalKind: Hashable {
    case remote(alias: String, session: String)
    case local(session: String, path: String)
}

/// A slot that shows the session's live terminal from `TerminalRegistry`.
/// Mounting attaches the shared view; unmounting only detaches it, so the
/// connection outlives this SwiftUI node.
struct TerminalPaneView: NSViewRepresentable {
    let kind: TerminalKind
    var translucent: Bool = false
    /// The terminal fills the card. A ring of padding around it would carry a
    /// different share of the translucent colour than the text area, and read as
    /// a second border; text touching the edge is the better trade.
    var contentInsets = NSEdgeInsets()

    func makeNSView(context: Context) -> NSView {
        // Container with no intrinsic size: SwiftUI stretches it; the container
        // lays the terminal out inside its insets. (TerminalView has its own
        // intrinsic size and would not stretch on its own in SwiftUI.)
        let container = TerminalContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.contentInsets = contentInsets
        container.kind = kind
        if case let .remote(alias, session) = kind {
            container.identifier = NSUserInterfaceItemIdentifier("\(FocusedTerminal.prefix)\(alias)/\(session)")
        }

        let term = TerminalRegistry.shared.terminal(for: kind)
        TerminalPaneView.applyAppearance(to: term, container: container, translucent: translucent)

        // The frame is not set here on purpose. A container starts at a
        // placeholder size, and giving that to a terminal whose session is
        // already running resizes the program to it — a live tmux rewraps its
        // screen to 40 by 15 and loses characters. The real size comes once the
        // pane is in a window.
        container.addSubview(term)
        container.content = term
        TerminalRegistry.shared.viewDidAttach(kind)
        // Lay out once more after SwiftUI's first sizing pass, at the size the
        // pane actually has. An earlier version shrank the pane by a row and
        // restored it to force a repaint; that left the last row unpainted,
        // which is worse than the blank pane it was meant to fix.
        sizeWhenOnScreen(container: container, term: term, attempt: 0)
        return container
    }

    /// The pane is measured only once it is in a window. SwiftUI probes a
    /// representable with sizes that are not the pane's — 2 by 1 cells among
    /// them — and every one of those reaches the program as a resize, which
    /// makes a remote tmux rewrap the screen and lose characters.
    private func sizeWhenOnScreen(
        container: TerminalContainerView, term: LocalProcessTerminalView, attempt: Int
    ) {
        DispatchQueue.main.async { [weak container, weak term] in
            guard let container, let term, term.superview === container else { return }
            guard container.window != nil else {
                guard attempt < 20 else {
                    PaneLog.log("gave up sizing pane=\(kind): never reached a window")
                    return
                }
                sizeWhenOnScreen(container: container, term: term, attempt: attempt + 1)
                return
            }
            container.applyContentFrame()
            // Frame and grid together: when the content stops halfway down the
            // pane, these two disagree, and the pair says which one is wrong.
            let grid = term.getWindowSize()
            PaneLog.log(
                "sized pane=\(kind) frame=\(Int(term.frame.width))x\(Int(term.frame.height))"
                + " grid=\(grid.ws_col)x\(grid.ws_row)")
            // Only now may the process start: it reads its size at startup.
            TerminalRegistry.shared.viewDidSize(kind)
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Don't call startProcess here: updateNSView runs many times. Appearance
        // is re-applied, so a change in Settings reaches panes already on screen
        // instead of waiting for the next time they are built.
        guard let container = nsView as? TerminalContainerView,
              let term = container.content as? LocalProcessTerminalView
        else { return }
        TerminalPaneView.applyAppearance(to: term, container: container, translucent: translucent)
    }

    /// Colours and font from Settings. The terminal always paints its own
    /// background, translucent or not: handing it a clear colour left every cell
    /// it did not redraw showing whatever was there before, which is a screen
    /// half old and half missing, and slow, since a large transparent layer is
    /// expensive to blend.
    static func applyAppearance(
        to term: LocalProcessTerminalView, container: NSView, translucent: Bool
    ) {
        let settings = SettingsStore.shared.settings
        let opacity = Appearance.clampTerminalOpacity(
            settings?.terminalOpacity ?? Appearance.defaultTerminalOpacity)
        // Both layers paint, each at the share that combines to the setting.
        let background = translucent
            ? NSColor(srgbRed: 0x10 / 255, green: 0x14 / 255, blue: 0x1A / 255,
                      alpha: Appearance.layerOpacity(forCombined: opacity))
            : NSColor(srgbRed: 0x14 / 255, green: 0x19 / 255, blue: 0x1F / 255, alpha: 1)
        let size = Appearance.clampTerminalFontSize(
            settings?.terminalFontSize ?? Appearance.defaultTerminalFontSize)
        if term.font.pointSize != size {
            term.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        term.nativeBackgroundColor = background
        term.nativeForegroundColor =
            NSColor(srgbRed: 0xC9 / 255, green: 0xCE / 255, blue: 0xD4 / 255, alpha: 1)
        term.wantsLayer = true
        term.layer?.isOpaque = !translucent
        term.requestRedraw()
        container.wantsLayer = true
        container.layer?.isOpaque = !translucent
        container.layer?.backgroundColor = background.cgColor
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let container = nsView as? TerminalContainerView,
              let term = container.content, term.superview === container else { return }
        term.removeFromSuperview()
        if let kind = container.kind {
            TerminalRegistry.shared.detach(kind)
        }
    }

    // Autoresizing masks did not keep the insets: after SwiftUI's first sizing
    // passes the terminal ended up the container's full height, overflowing the
    // top edge and eating the first row. Explicit layout is deterministic.
    final class TerminalContainerView: NSView {
        var contentInsets = NSEdgeInsets()
        var kind: TerminalKind?
        weak var content: NSView?

        var contentFrame: NSRect {
            NSRect(
                x: contentInsets.left,
                y: contentInsets.bottom,
                width: max(1, bounds.width - contentInsets.left - contentInsets.right),
                height: max(1, bounds.height - contentInsets.top - contentInsets.bottom)
            )
        }

        override func layout() {
            super.layout()
            applyContentFrame()
        }

        /// `needsDisplay` is dropped on the floor by SwiftTerm's Metal
        /// renderer: `draw(_:)` returns at once and frames come from its own
        /// driver, so only `requestRedraw()` marks a frame.
        func redrawContent() {
            (content as? TerminalView)?.requestRedraw()
        }

        /// Cell size in points, learned from a frame the terminal accepted. It
        /// comes from the font, so one reading is good until the font changes.
        private var cellSize: CGSize?

        /// Gives the terminal the pane's size, but never a size that is only a
        /// step in SwiftUI's measurement or a window being taken apart: the
        /// program on the other end resizes with it, and a remote tmux that
        /// rewraps to 2 columns and back comes back with characters missing.
        func applyContentFrame() {
            guard let content else { return }
            guard window != nil else { return }
            let target = contentFrame
            if let cell = cellSize, cell.width > 0, cell.height > 0 {
                let cols = Int(target.width / cell.width)
                let rows = Int(target.height / cell.height)
                guard TerminalSizeGuard.isUsable(cols: cols, rows: rows) else {
                    PaneLog.log("skipped pane size cols=\(cols) rows=\(rows)")
                    return
                }
            }
            content.frame = target
            if let term = content as? LocalProcessTerminalView {
                let grid = term.getWindowSize()
                if grid.ws_col > 0, grid.ws_row > 0 {
                    cellSize = CGSize(
                        width: target.width / CGFloat(grid.ws_col),
                        height: target.height / CGFloat(grid.ws_row))
                }
            }
            redrawContent()
        }

        /// Kept as a no-op: masking the container to the ring also clipped the
        /// terminal inside it, and every pane went blank.
        func updateRingMask() {}
        var hasRingMask = false

        override func resizeSubviews(withOldSize oldSize: NSSize) {
            applyContentFrame()
        }
    }
}
