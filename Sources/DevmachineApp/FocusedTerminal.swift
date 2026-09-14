import AppKit

enum FocusedTerminal {
    static let prefix = "term:"

    // The terminal that currently owns keyboard focus, found by walking up from the
    // window's first responder to the container tagged by TerminalPaneView.
    @MainActor
    static func ref() -> SessionRef? {
        guard var view = NSApp.keyWindow?.firstResponder as? NSView else { return nil }
        while true {
            if let id = view.identifier?.rawValue, id.hasPrefix(prefix) {
                let body = id.dropFirst(prefix.count)
                guard let slash = body.firstIndex(of: "/") else { return nil }
                return SessionRef(alias: String(body[..<slash]), name: String(body[body.index(after: slash)...]))
            }
            guard let parent = view.superview else { return nil }
            view = parent
        }
    }
}
