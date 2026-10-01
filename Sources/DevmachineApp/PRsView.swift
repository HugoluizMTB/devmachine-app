import SwiftUI
import DevmachineCore

struct PRsView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var store: PRStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .animation(.easeOut(duration: 0.2), value: store.showsSkeleton)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
    }

    private var canFavorite: Bool { store.selectedOwner != allOwnersSentinel }

    private var header: some View {
        HStack(spacing: m.space.md) {
            Picker("", selection: Binding(
                get: { store.selectedOwner },
                set: { store.select($0) }
            )) {
                ForEach(store.orderedOwners, id: \.self) { owner in
                    Text(ownerLabel(owner)).tag(owner)
                }
            }
            .labelsHidden()
            .frame(maxWidth: m.pt(190))

            DMIconButton(
                systemImage: store.isFavorite(store.selectedOwner) ? "star.fill" : "star",
                tint: store.isFavorite(store.selectedOwner) ? .yellow : .secondary
            ) {
                store.toggleFavorite(store.selectedOwner)
            }
            .disabled(!canFavorite)
            .help(store.isFavorite(store.selectedOwner) ? "Unfavorite" : "Favorite — pins it to the top")

            Spacer()

            if store.isLoading && !store.showsSkeleton {
                ProgressView().controlSize(.small)
            }
            DMIconButton(systemImage: "arrow.clockwise", tint: nil) { store.refresh() }
                .help("Refresh")
        }
        .padding(m.pt(10))
    }

    private func ownerLabel(_ owner: String) -> String {
        if owner == allOwnersSentinel { return "All orgs" }
        return store.isFavorite(owner) ? "★ \(owner)" : owner
    }

    @ViewBuilder
    private var content: some View {
        if let err = store.errorText {
            DMStatusView(
                kind: .failed(
                    title: "Couldn't load pull requests", message: err, retry: { store.refresh() }),
                fillsHeight: false)
        } else if store.showsSkeleton {
            PRListSkeleton()
                .padding(.vertical, m.space.sm)
                .transition(.opacity)
        } else if store.forest.isEmpty {
            DMStatusView(
                kind: .empty(
                    systemImage: "checkmark.circle",
                    text: store.isLoading ? "Loading…" : "No open pull requests"),
                fillsHeight: false)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: m.space.xxs) {
                    ForEach(store.forest, id: \.pr.id) { item in
                        PRRowView(pr: item.pr, depth: item.depth)
                    }
                }
                .padding(.vertical, m.space.sm)
            }
            .frame(maxHeight: .infinity)
            .transition(.opacity)
        }
    }
}

/// The pull request list before its first answer: rows in `PRRowView`'s
/// sizes, as many as the panel holds.
private struct PRListSkeleton: View {
    @Environment(\.dmMetrics) private var m
    var body: some View {
        DMSkeleton {
            DMSkeletonRows(rowHeight: 40) { index in
                HStack(spacing: m.space.md) {
                    DMSkeletonBlock(width: .fixed(8), height: 8, radius: 4)
                    DMSkeletonText(size: 13, width: .varied(index, shares: [0.7, 0.5, 0.82, 0.6, 0.44, 0.76]))
                    DMSkeletonText(size: 11, width: .fixed([96, 120, 84][index % 3]))
                    DMSkeletonBlock(width: .fixed(24), height: 24, radius: 12)
                }
                .padding(.horizontal, m.pt(10))
                .padding(.vertical, m.pt(7))
                .padding(.horizontal, m.space.sm)
                .padding(.bottom, m.space.xxs)
            }
        }
    }
}
