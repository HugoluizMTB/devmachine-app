import Foundation

/// Who answers a mouse gesture in a terminal pane. The pane owns selection: a
/// drag selects text here even when the program asked for the mouse, because
/// tmux asks for it in every remote session and then draws a selection of its
/// own, in another colour, that never reaches the Mac's clipboard the same way.
/// Local, ssh and mosh panes therefore select, copy and clear alike.
public enum TerminalPointer {
    public enum Gesture: Equatable, Sendable {
        case press
        case drag
        case release(dragged: Bool, clickCount: Int, command: Bool)
        case wheel
    }

    public enum Route: Equatable, Sendable {
        /// The terminal's own selection: start, extend, clear, word, line.
        case selection
        /// The terminal's own selection, then the same click for a program
        /// that reads the mouse (a tmux pane or window, a cursor in an editor).
        case selectionThenProgram
        /// The terminal's rule: the program when it reads the mouse, which is
        /// how tmux scrolls its history, the scrollback otherwise.
        case terminalDefault
    }

    public static func route(_ gesture: Gesture) -> Route {
        switch gesture {
        case .press, .drag:
            return .selection
        case let .release(dragged, clickCount, command):
            return !dragged && clickCount == 1 && !command ? .selectionThenProgram : .selection
        case .wheel:
            return .terminalDefault
        }
    }

    /// How far the pointer travels before a press becomes a drag. Below it a
    /// hand that shakes on a click would select one letter and replace the
    /// clipboard with it.
    public static let dragThreshold: CGFloat = 3

    public static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        max(abs(end.x - start.x), abs(end.y - start.y)) >= dragThreshold
    }

    /// A drag, a double-click (word) and a triple-click (line) put their text
    /// on the clipboard when the setting is on; a plain click only clears.
    public static func copiesOnRelease(enabled: Bool, dragged: Bool, clickCount: Int, hasSelection: Bool) -> Bool {
        enabled && hasSelection && (dragged || clickCount >= 2)
    }
}

/// A clipboard write a program sent through OSC 52 (tmux's copy mode, an
/// editor's yank). It is taken only from the pane that has the keyboard, so a
/// session in the background cannot replace what you copied.
public enum TerminalClipboard {
    /// Far above any selection a person makes, well below what would stall the
    /// pasteboard.
    public static let maxWriteBytes = 1 << 20

    public static func text(fromWrite content: Data, paneIsFocused: Bool) -> String? {
        guard paneIsFocused, !content.isEmpty, content.count <= maxWriteBytes else { return nil }
        return String(data: content, encoding: .utf8)
    }
}
