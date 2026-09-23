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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Button {
                store.toggleFavorite(store.selectedOwner)
            } label: {
                Image(systemName: store.isFavorite(store.selectedOwner) ? "star.fill" : "star")
                    .foregroundColor(store.isFavorite(store.selectedOwner) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canFavorite)
            .opacity(canFavorite ? 1 : 0.35)
            .help(store.isFavorite(store.selectedOwner) ? "Unfavorite" : "Favorite — pins it to the top")

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
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
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.dm(12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { store.refresh() }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        } else if store.forest.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(store.isLoading ? "Loading…" : "No open pull requests")
                    .font(.dm(12))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
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
