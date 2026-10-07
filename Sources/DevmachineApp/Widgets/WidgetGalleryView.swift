import SwiftUI
import DevmachineCore

struct WidgetGalleryView: View {
    let catalog: WidgetCatalog?
    let failure: String?
    let blockedReason: String?
    let onAdd: (CatalogWidget) -> Void
    let onRetry: () -> Void
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: "Add a widget")
                .font(.dm(13, weight: .semibold))
            if let blockedReason {
                Text(verbatim: blockedReason)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let catalog {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: m.space.xs) {
                        ForEach(WidgetGallery.entries(catalog, surface: DefaultBoard.surface)) { row($0, in: catalog) }
                    }
                }
            } else if let failure {
                DMErrorStateView(state: DMErrorState(title: "Could not fetch packages", message: failure), retry: onRetry)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(m.space.lg)
        .frame(width: m.card.sheet)
        .frame(maxHeight: m.pt(480))
    }

    private func row(_ widget: CatalogWidget, in catalog: WidgetCatalog) -> some View {
        HStack(alignment: .top, spacing: m.space.md) {
            VStack(alignment: .leading, spacing: m.space.xxs) {
                Text(verbatim: WidgetTitle.make(type: widget.name, in: catalog))
                    .font(.dm(12, weight: .semibold))
                Text(verbatim: widget.name)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                Text(verbatim: widget.summary)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if !widget.available {
                    unavailableHint(widget)
                }
            }
            Spacer(minLength: m.space.sm)
            if widget.available {
                DMButton("Add", variant: .outline, size: .small) { onAdd(widget) }
                    .disabled(blockedReason != nil)
            }
        }
        .padding(m.space.sm)
    }

    private func unavailableHint(_ widget: CatalogWidget) -> some View {
        let hint = WidgetGallery.hint(widget.unavailableReason)
        return VStack(alignment: .leading, spacing: m.space.xs) {
            Label {
                Text(verbatim: hintTitle(hint.advice))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "shippingbox")
            }
            .font(.dm(11, weight: .semibold))
            if let command = hint.command {
                DMCommandBlock(command, wraps: true)
            }
        }
        .padding(.top, m.space.xs)
    }

    private func hintTitle(_ advice: String) -> String {
        advice.isEmpty ? "Add package" : advice.prefix(1).uppercased() + advice.dropFirst()
    }
}
