import SwiftUI
import DevmachineCore

/// A reason every listed widget shares (the board cannot change) reads
/// once above the list, as Home always showed it; any other sits on its row.
enum WidgetGalleryReasons {
    static func shared(_ entries: [CatalogWidget], _ reason: (CatalogWidget) -> String?) -> String? {
        guard let first = entries.first.flatMap(reason) else { return nil }
        return entries.allSatisfy({ reason($0) == first }) ? first : nil
    }
}

/// A sidebar lists its built-in widgets even while the catalog is loading
/// or failed, so a removed Workspaces list can come back offline; Home has
/// none, so it waits for the catalog as before.
enum WidgetGalleryContent: Equatable {
    case list(failure: String?, loading: Bool)
    case failure(String)
    case loading

    static func of(hasCatalog: Bool, entries: Int, failure: String?) -> WidgetGalleryContent {
        if hasCatalog { return .list(failure: nil, loading: false) }
        if entries > 0 { return .list(failure: failure, loading: failure == nil) }
        if let failure { return .failure(failure) }
        return .loading
    }
}

struct WidgetGalleryView: View {
    let surface: String
    let catalog: WidgetCatalog?
    let entries: [CatalogWidget]
    let failure: String?
    let blockedReason: (CatalogWidget) -> String?
    let onAdd: (CatalogWidget) -> Void
    let onRetry: () -> Void
    var templates: [InlineWidgetTemplate] = []
    var canMakeWidgets = true
    var onNewWidget: (InlineWidgetTemplate) -> Void = { _ in }
    @Environment(\.dmMetrics) private var m

    var body: some View {
        let sharedReason = WidgetGalleryReasons.shared(entries, blockedReason)
        return VStack(alignment: .leading, spacing: m.space.md) {
            HStack {
                Text(verbatim: "Add a widget").font(.dm(13, weight: .semibold))
                Spacer()
                if !templates.isEmpty {
                    Menu {
                        ForEach(templates) { template in
                            Button { onNewWidget(template) } label: {
                                Text(verbatim: template.title)
                            }
                        }
                    } label: {
                        Text(verbatim: "New widget")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!canMakeWidgets || sharedReason != nil)
                }
            }
            if let sharedReason {
                Text(verbatim: sharedReason)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch WidgetGalleryContent.of(hasCatalog: catalog != nil, entries: entries.count, failure: failure) {
            case let .list(failure, loading):
                if let failure {
                    DMBanner(message: "Could not fetch packages: \(failure)", lineLimit: 3) {
                        DMButton("Try again", variant: .ghost, size: .small, action: onRetry)
                    }
                } else if loading {
                    ProgressView().controlSize(.small)
                }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: m.space.xs) {
                        ForEach(entries) { row($0, in: catalog, showsReason: sharedReason == nil) }
                    }
                }
            case let .failure(failure):
                DMErrorStateView(state: DMErrorState(title: "Could not fetch packages", message: failure), retry: onRetry)
            case .loading:
                ProgressView().controlSize(.small)
            }
        }
        .padding(m.space.lg)
        .frame(width: m.card.sheet)
        .frame(maxHeight: m.pt(480))
    }

    private func row(_ widget: CatalogWidget, in catalog: WidgetCatalog?, showsReason: Bool) -> some View {
        let reason = blockedReason(widget)
        return HStack(alignment: .top, spacing: m.space.md) {
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
                if let reason, showsReason {
                    Text(verbatim: reason)
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !widget.available {
                    unavailableHint(widget)
                }
            }
            Spacer(minLength: m.space.sm)
            if widget.available {
                DMButton("Add", variant: .outline, size: .small) { onAdd(widget) }
                    .disabled(reason != nil)
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
