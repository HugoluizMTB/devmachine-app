import SwiftUI
import DevmachineCore

/// The corner card when this app needs a newer CLI or packages release for
/// Home. It stays until the gap closes: Home cannot work around it.
struct WidgetCompatBanner: View {
    @ObservedObject var store: WidgetCompatibilityStore
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if let gap = store.gap {
            VStack(alignment: .leading, spacing: m.row.horizontal) {
                UpdateToastHeader(
                    icon: "square.grid.2x2", tint: .orange, title: CompatibilityCopy.title(gap),
                    note: CompatibilityCopy.note(gap, manifest: store.manifest))
                DMCommandBlock(gap.command.commandLine, wraps: true)
                switch store.phase {
                case .running:
                    UpdateProgressView(label: "Updating…")
                case .failed(let error):
                    DMErrorStateView(state: error, retry: { Task { await store.runUpdate() } })
                case .idle:
                    HStack {
                        Spacer(minLength: 0)
                        DMButton("Run update", size: .small) { Task { await store.runUpdate() } }
                    }
                }
            }
            .frame(width: m.card.banner, alignment: .leading)
            .dmToastChrome()
        }
    }
}
