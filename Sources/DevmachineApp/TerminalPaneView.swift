import SwiftUI
import AppKit
import SwiftTerm
import DevmachineCore

enum TerminalKind: Hashable {
    case remote(alias: String, session: String)
    case operador
}

/// A slot that shows the session's live terminal from `TerminalRegistry`.
/// Mounting attaches the shared view; unmounting only detaches it, so the
/// connection outlives this SwiftUI node.
struct TerminalPaneView: NSViewRepresentable {
    let kind: TerminalKind
    var translucent: Bool = false
    var contentInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

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
        let background = translucent
            ? NSColor(srgbRed: 0x10 / 255, green: 0x14 / 255, blue: 0x1A / 255, alpha: 0.66)
            : NSColor(srgbRed: 0x14 / 255, green: 0x19 / 255, blue: 0x1F / 255, alpha: 1)
        // Translucent: only the container paints the background. If the terminal
        // painted the same alpha color too, the text area would double-blend and
        // read as a different shade than the padding ring around it.
        term.nativeBackgroundColor = translucent ? .clear : background
        term.wantsLayer = true
        term.layer?.isOpaque = !translucent
        container.wantsLayer = true
        container.layer?.isOpaque = !translucent
        container.layer?.backgroundColor = background.cgColor
        term.nativeForegroundColor = NSColor(srgbRed: 0xC9 / 255, green: 0xCE / 255, blue: 0xD4 / 255, alpha: 1)

        // Inset the terminal so text does not sit at 0,0; the container paints the
        // same background so the padding reads as part of the card.
        term.frame = container.contentFrame
        container.addSubview(term)
        container.content = term
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Don't call startProcess here: updateNSView runs many times.
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
            content?.frame = contentFrame
        }

        override func resizeSubviews(withOldSize oldSize: NSSize) {
            content?.frame = contentFrame
        }
    }
}
