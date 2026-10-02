import SwiftUI

/// Above Local while the configuration holds no machine: the way to a
/// server or a machine on this Mac. Local sessions work without one, so it
/// asks nothing and blocks nothing.
struct AddMachineSidebarButton: View {
    @Environment(\.dmMetrics) private var m
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            Text(verbatim: "No machine yet. Add a server you have, or one on this Mac.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            DMButton("Add a machine", systemImage: "plus", variant: .outline, size: .small, fillsWidth: true,
                     action: action)
        }
        .padding(m.space.md)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }
}
