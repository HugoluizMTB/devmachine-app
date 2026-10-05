import SwiftUI
import DevmachineCore

/// The target the page acts on and the rows ticked for it. A selection
/// belongs to one target, so choosing another one empties it.
struct PackagesPageState: Equatable {
    private(set) var target: PackageTarget?
    var selection = PackageSelection()

    init(target: PackageTarget? = nil) {
        self.target = target
    }

    mutating func choose(_ next: PackageTarget?) {
        guard next != target else { return }
        target = next
        selection.clear()
    }

    /// A reload that no longer lists the target goes back to every machine.
    mutating func keep(targets: [PackageTarget]) {
        if let target, !targets.contains(target) { choose(nil) }
    }
}

/// Settings → Packages: the catalog and the local packages, what each
/// machine and workspace has, and a selection that `packages add|rm` saves
/// before the job center asks to sync. It owns its scrolling so the Apply
/// bar stays in view under the rows.
struct PackagesSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var store: PackagesStore = .shared
    @State private var page: PackagesPageState
    @State private var filter = PackageFilter()
    @State private var confirming = false

    init(store: PackagesStore = .shared, page: PackagesPageState = PackagesPageState()) {
        self.store = store
        _page = State(initialValue: page)
    }

    private var target: PackageTarget? { page.target }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.requestLoad() }
        .onChange(of: store.snapshot?.targets) { _, targets in page.keep(targets: targets ?? []) }
        .confirmationDialog(
            "Change packages on \(target?.title ?? "")?",
            isPresented: $confirming,
            presenting: target.map { ($0, changes) }
        ) { target, changes in
            Button("Apply") {
                Task { if await store.apply(changes, on: target) { page.selection.clear() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _, changes in
            Text(verbatim: Self.confirmMessage(changes))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading where store.snapshot == nil:
            PackagesSkeleton()
        case let .failed(error) where store.snapshot == nil:
            DMErrorStateView(state: error, retry: { store.requestLoad() })
        default:
            if let snapshot = store.snapshot {
                loaded(snapshot)
            }
        }
    }

    @ViewBuilder
    private func loaded(_ snapshot: PackagesSnapshot) -> some View {
        let statuses = target.map { snapshot.statuses(for: $0) }
        PackagesHeader(
            targets: snapshot.targets, target: Binding(get: { page.target }, set: { page.choose($0) }),
            filter: $filter, categories: PackageFilter.categories(in: snapshot.entries))
        if let target, let statuses, let request = PackagePending.syncRequest(statuses: statuses, target: target) {
            HStack(spacing: m.space.md) {
                Text(verbatim: "Some packages wait for a sync on \(request.machine).")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMButton("Sync now", variant: .outline, size: .small) { store.syncPending(on: target) }
                Spacer(minLength: 0)
            }
        }
        if let error = store.applyError {
            DMErrorStateView(state: error, retry: nil)
            DMButton("Dismiss", variant: .ghost, size: .small) { store.applyError = nil }
        }
        ScrollView(.vertical) {
            rows(snapshot, statuses: statuses)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: .infinity)
        if let target, !page.selection.names.isEmpty {
            footer(target: target, changes: page.selection.changes(statuses: statuses ?? [:]))
        }
    }

    @ViewBuilder
    private func rows(_ snapshot: PackagesSnapshot, statuses: [String: PackageStatus]?) -> some View {
        let rows = filter.apply(snapshot.entries, statuses: statuses)
        if filter.tab == .local, !snapshot.entries.contains(where: \.isLocal) {
            localEmptyState(snapshot.configDirectory)
        } else if rows.isEmpty {
            Text(verbatim: "No package matches.")
                .font(.dm(11.5))
                .foregroundStyle(Color.dmMuted)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                    DMTableRow(index: index) {
                        PackageRow(
                            entry: entry, target: target, status: statuses.map { $0[entry.name] ?? .available },
                            isSelected: page.selection.names.contains(entry.name),
                            toggle: { page.selection.toggle(entry.name) })
                    }
                }
            }
        }
    }

    private var changes: PackageChanges {
        guard let target, let snapshot = store.snapshot else { return PackageChanges(adds: [], removes: []) }
        return page.selection.changes(statuses: snapshot.statuses(for: target))
    }

    private func localEmptyState(_ directory: String?) -> some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: "No local packages. Put one in \(directory ?? "the configuration folder")/packages/.")
                .font(.dm(11.5))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            DMCommandBlock("devmachine packages new <name>")
        }
    }

    private func footer(target: PackageTarget, changes: PackageChanges) -> some View {
        HStack(spacing: m.space.md) {
            Text(verbatim: "\(changes.adds.count) to install · \(changes.removes.count) to remove on \(target.title)")
                .font(.dm(12, weight: .medium))
                .foregroundStyle(Color.dmRowText)
            Spacer(minLength: m.space.md)
            DMButton("Clear", variant: .ghost, size: .small) { page.selection.clear() }
            DMButton("Apply", variant: .primary, size: .small, isLoading: store.applying) { confirming = true }
                .disabled(changes.isEmpty)
        }
        .padding(m.space.md)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }

    static let removalNote =
        "Removing stops managing a package; the software stays on the machine until you remove it by hand."

    static func confirmMessage(_ changes: PackageChanges) -> String {
        var lines: [String] = []
        if !changes.adds.isEmpty { lines.append("Install: \(changes.adds.joined(separator: ", "))") }
        if !changes.removes.isEmpty {
            lines.append("Remove: \(changes.removes.joined(separator: ", "))")
            lines.append(removalNote)
        }
        return lines.joined(separator: "\n")
    }
}

/// The target, the tabs, the search and the filters above the package rows.
struct PackagesHeader: View {
    let targets: [PackageTarget]
    @Binding var target: PackageTarget?
    @Binding var filter: PackageFilter
    let categories: [String]
    @Environment(\.dmMetrics) private var m

    private static let scopes: [String?] = [nil, "machine", "workspace"]

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            HStack(spacing: m.space.lg) {
                Picker("Target", selection: $target) {
                    Text(verbatim: "All machines").tag(PackageTarget?.none)
                    ForEach(targets, id: \.self) { target in
                        Text(verbatim: target.title).tag(PackageTarget?.some(target))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: m.pt(180))
                DMTabStrip(
                    tabs: PackageTab.allCases, selection: $filter.tab, title: \.title,
                    fontSize: 12, grouped: true)
                    .fixedSize()
                DMSearchField(prompt: "Search packages", text: $filter.query)
                    .padding(.horizontal, m.row.horizontal)
                    .padding(.vertical, m.space.sm)
                    .dmSurface(Color.dmSelection, radius: DMRadius.row)
            }
            HStack(alignment: .top, spacing: m.space.lg) {
                FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            toggle(category)
                        } label: {
                            Text(verbatim: category).font(.dm(11))
                        }
                        .buttonStyle(.dmChip(selected: filter.categories.contains(category)))
                    }
                }
                Spacer(minLength: 0)
                DMTabStrip(
                    tabs: Self.scopes, selection: $filter.scope, title: Self.scopeTitle,
                    fontSize: 11, horizontalPadding: 8, verticalPadding: 3, grouped: true)
                    .fixedSize()
            }
        }
    }

    private func toggle(_ category: String) {
        if filter.categories.remove(category) == nil { filter.categories.insert(category) }
    }

    private static func scopeTitle(_ scope: String?) -> String {
        switch scope {
        case "machine": return "Machine"
        case "workspace": return "Workspace"
        default: return "All"
        }
    }
}

/// Rows shaped like package rows while the first read runs.
private struct PackagesSkeleton: View {
    @Environment(\.dmMetrics) private var m

    var body: some View {
        DMSkeleton {
            VStack(alignment: .leading, spacing: m.space.md) {
                ForEach(0..<6, id: \.self) { index in
                    HStack(alignment: .top, spacing: m.space.md) {
                        DMSkeletonBlock(width: .fixed(14), height: 14)
                        VStack(alignment: .leading, spacing: m.space.xs) {
                            DMSkeletonText(size: 13, weight: .semibold, width: .fixed(120))
                            DMSkeletonText(size: 11.5, width: .varied(index))
                        }
                    }
                    .padding(.horizontal, m.row.horizontal)
                    .padding(.vertical, m.space.sm)
                }
            }
        }
    }
}
