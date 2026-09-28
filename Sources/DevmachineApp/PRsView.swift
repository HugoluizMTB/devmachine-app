import SwiftUI
import DevmachineCore

struct PRsView: View {
    @EnvironmentObject var store: PRStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
    }

    private var canFavorite: Bool { store.selectedOwner != allOwnersSentinel }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { store.selectedOwner },
                set: { store.select($0) }
            )) {
                ForEach(store.orderedOwners, id: \.self) { owner in
                    Text(ownerLabel(owner)).tag(owner)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 190)

            DMIconButton(
                systemImage: store.isFavorite(store.selectedOwner) ? "star.fill" : "star",
                tint: store.isFavorite(store.selectedOwner) ? .yellow : .secondary
            ) {
                store.toggleFavorite(store.selectedOwner)
            }
            .disabled(!canFavorite)
            .help(store.isFavorite(store.selectedOwner) ? "Unfavorite" : "Favorite — pins it to the top")

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            DMIconButton(systemImage: "arrow.clockwise", tint: nil) { store.refresh() }
                .help("Refresh")
        }
        .padding(10)
    }

    private func ownerLabel(_ owner: String) -> String {
        if owner == allOwnersSentinel { return "All orgs" }
        return store.isFavorite(owner) ? "★ \(owner)" : owner
    }

    @ViewBuilder
    private var content: some View {
        if let err = store.errorText {
            DMStatusView(
                kind: .failed(message: err, retry: { store.refresh() }), fillsHeight: false)
        } else if store.forest.isEmpty {
            DMStatusView(
                kind: .empty(
                    systemImage: "checkmark.circle",
                    text: store.isLoading ? "Loading…" : "No open pull requests"),
                fillsHeight: false)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.forest, id: \.pr.id) { item in
                        PRRowView(pr: item.pr, depth: item.depth)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
