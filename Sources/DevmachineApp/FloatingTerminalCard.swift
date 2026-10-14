import SwiftUI

enum FloatingCardLayout {
    /// Space between a card and the pane edge (single session and session grid).
    static let margin: CGFloat = 8
    /// Space between two cards in a session grid.
    static let gap: CGFloat = 8
}

struct FloatingTerminalCard: ViewModifier {
    func body(content: Content) -> some View {
        // No stroke around the card: with a translucent pane it read as a second
        // border, next to the ring of padding, and the pane is meant to look
        // like one surface.
        content
            .clipShape(RoundedRectangle(cornerRadius: DMRadius.terminal, style: .continuous))
    }
}

extension View {
    func floatingCard() -> some View {
        modifier(FloatingTerminalCard())
    }
}
