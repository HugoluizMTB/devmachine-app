import SwiftUI

/// A quiet uppercase tag naming what a thing is (a link's kind, a DNS record
/// type). Every kind looks the same: the word says the kind, colour does not.
/// A badge that means a status (PUBLISHED, PENDING) is a `DMPill` instead.
struct DMKindLabel: View {
    static let textHex: UInt32 = 0x8A9199
    static let fillOpacity: Double = 0.07

    let text: String
    @Environment(\.dmMetrics) private var m

    var body: some View {
        Text(text)
            .font(.dm(9, weight: .semibold))
            .foregroundStyle(Color(hex: Self.textHex))
            .lineLimit(1)
            .padding(.horizontal, m.space.sm)
            .padding(.vertical, m.space.xxs)
            .background(Color.white.opacity(Self.fillOpacity), in: Capsule())
    }
}
