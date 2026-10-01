import SwiftUI
import DevmachineCore

/// GitHub's own scheme, so a merged PR never passes for an open one.
extension PRStateKind {
    var symbol: String {
        switch self {
        case .open, .draft: return "arrow.triangle.pull"
        case .merged: return "arrow.triangle.merge"
        case .closed: return "xmark.octagon"
        }
    }

    var colorHex: UInt32 {
        switch self {
        case .open: return 0x3FB950
        case .draft: return 0x8B949E
        case .merged: return 0xA371F7
        case .closed: return 0xF85149
        }
    }

    var color: Color { Color(hex: colorHex) }
}

/// A pull request's state glyph, the same in every list that shows one.
struct DMPRStateIcon: View {
    let state: PRStateKind
    var size: CGFloat = 12
    @Environment(\.dmMetrics) private var m

    var body: some View {
        Image(systemName: state.symbol)
            .font(.dm(size, weight: .semibold))
            .foregroundStyle(state.color)
            .frame(width: m.pt(size + 4))
            .accessibilityLabel(Text(state.accessibilityLabel))
    }
}
