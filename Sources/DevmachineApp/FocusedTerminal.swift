import AppKit
import DevmachineCore

enum FocusedTerminal {
    static let prefix = "term:"

    /// The tag a pane carries so the focused one can be named later. A local
    /// session is tagged under the Local workspace's alias, which is what a
    /// `SessionRef` for it uses.
    static func tag(for kind: TerminalKind) -> String {
        switch kind {
        case let .remote(alias, session): return "\(prefix)\(alias)/\(session)"
        case let .local(session, _): return "\(prefix)\(Workspace.local.alias)/\(session)"
        }
    }

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
