import SwiftUI
import AppKit

/// A 6pt drag column between two panes. Paints nothing: the panes' own
/// backgrounds meet, with no hairline in between.
struct ResizeHandle: View {
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { onDrag($0.translation.width) }
                    .onEnded { _ in onEnd() }
            )
    }
}
