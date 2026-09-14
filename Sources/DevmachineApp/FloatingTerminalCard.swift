import SwiftUI

enum FloatingCardLayout {
    /// Space between a card and the pane edge (single session and stack grid).
    static let margin: CGFloat = 8
    /// Space between two cards in a stack grid.
    static let gap: CGFloat = 8
}

struct FloatingTerminalCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func floatingCard() -> some View {
        modifier(FloatingTerminalCard())
    }
}
