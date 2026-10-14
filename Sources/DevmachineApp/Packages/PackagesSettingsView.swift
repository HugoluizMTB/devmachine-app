import SwiftUI
import AppKit
import DevmachineCore

/// What the Packages page shows and what the person has picked: the machine
/// and workspace dropdowns, the ticked packages and where the bar sends
/// them, and the one row opened on its own actions.
struct PackagesPageState: Equatable {
    var machine: String?
    var workspace: String?
    var selection: Set<String> = []
    var bulkDestinations: Set<PackageTarget> = []
    private(set) var expanded: String?
    var rowDestinations: Set<PackageTarget> = []

    /// "Packages on this machine" or "Packages for this workspace": the
    /// page opens with that dropdown set. Nil when nothing asked.
    static func requested(machine: String?, workspace: String?) -> PackagesPageState? {
        guard machine != nil || workspace != nil else { return nil }
        var page = PackagesPageState()
        page.machine = machine
        page.workspace = workspace
        return page
    }

    mutating func toggle(_ name: String) {
        if selection.remove(name) == nil { selection.insert(name) }
    }

    mutating func toggleExpanded(_ name: String) {
        expanded = expanded == name ? nil : name
        rowDestinations = []
    }

    mutating func clearSelection() {
        selection = []
        bulkDestinations = []
    }

    mutating func closeRow() {
        expanded = nil
        rowDestinations = []
    }

    /// A reload that no longer lists a dropdown's choice or a destination
    /// lets go of it.
    mutating func keep(targets: [PackageTarget]) {
        if let machine, !targets.contains(where: { $0.scope == "machine" && $0.name == machine }) { self.machine = nil }
        if let workspace, !targets.contains(where: { $0.scope == "workspace" && $0.name == workspace }) {
            self.workspace = nil
        }
        bulkDestinations.formIntersection(targets)
        rowDestinations.formIntersection(targets)
    }

    /// The machine and workspace the dropdowns picked; none means the page
    /// looks at every one.
    func focus(in targets: [PackageTarget]) -> [PackageTarget] {
        targets.filter { target in
            switch target {
            case let .machine(name, _): return name == machine
            case let .workspace(name, _): return name == workspace
            }
        }
    }

    /// One dropdown alone narrows the list to packages of its kind.
    var scope: String? {
        switch (machine, workspace) {
        case (.some, nil): return "machine"
        case (nil, .some): return "workspace"
        default: return nil
        }
    }
}

/// An action waiting for the person to confirm it.
struct PackagesPendingAction: Identifiable {
    let id = UUID()
    let action: PackageAction
    let batch: PackageBatch
    let fromRow: Bool
}

/// Settings → Packages: the catalog and the local packages, where each one
/// is, and the actions that `packages add|rm` save before the job center
/// asks to sync. It owns its scrolling so the bar stays in view under the rows.
struct PackagesSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @Environment(\.harnessSettingsFacade) private var harnessFacade
    @ObservedObject var store: PackagesStore = .shared
    @State private var page: PackagesPageState
    @State private var filter = PackageFilter()
    @State private var pending: PackagesPendingAction?
    @State private var choosingHarness = false

    init(store: PackagesStore = .shared, page: PackagesPageState = PackagesPageState()) {
        self.store = store
        _page = State(initialValue: page)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.requestLoad() }
        .onChange(of: store.snapshot?.targets) { _, targets in page.keep(targets: targets ?? []) }
        .confirmationDialog(
            pending.map { Self.confirmTitle($0.action) } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { pending in
            Button(pending.action == .install ? "Install" : "Remove", role: pending.action == .remove ? .destructive : nil) {
                Task {
                    guard await store.apply(pending.batch) else { return }
                    if pending.fromRow { page.closeRow() } else { page.clearSelection() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(verbatim: Self.confirmMessage(pending.batch, action: pending.action))
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
        let statuses = Self.statuses(snapshot)
        let focus = page.focus(in: snapshot.targets)
        HStack(alignment: .top, spacing: m.space.lg) {
            PackagesHeader(
                targets: snapshot.targets, page: $page, filter: $filter,
                categories: PackageFilter.categories(in: snapshot.entries))
            DMButton("New package", systemImage: "plus", variant: .outline, size: .small) { choosingHarness = true }
                .popover(isPresented: $choosingHarness, arrowEdge: .bottom) {
                    newPackagePicker(configDirectory: snapshot.configDirectory)
                }
        }
        pendingSyncLine(snapshot, statuses: statuses)
        if let error = store.applyError {
            DMErrorStateView(state: error, retry: nil)
            DMButton("Dismiss", variant: .ghost, size: .small) { store.applyError = nil }
        }
        ScrollView(.vertical) {
            rows(snapshot, statuses: statuses, focus: focus)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: .infinity)
        if !page.selection.isEmpty {
            bulkBar(snapshot, statuses: statuses)
        }
    }

    @ViewBuilder
    private func rows(
        _ snapshot: PackagesSnapshot, statuses: [PackageTarget: [String: PackageStatus]], focus: [PackageTarget]
    ) -> some View {
        let rows = Self.narrowed(filter, scope: page.scope).apply(snapshot.entries, statuses: Self.installedAnywhere(on: focus, statuses: statuses))
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
                        VStack(alignment: .leading, spacing: 0) {
                            PackageRow(
                                entry: entry,
                                placements: PackagePlacement.list(
                                    for: entry, targets: focus.isEmpty ? snapshot.targets : focus, statuses: statuses),
                                isSelected: page.selection.contains(entry.name),
                                isExpanded: page.expanded == entry.name,
                                systemFit: snapshot.systemFit(entry, on: focus, statuses: statuses),
                                toggleSelected: { page.toggle(entry.name) },
                                toggleExpanded: { page.toggleExpanded(entry.name) })
                            if page.expanded == entry.name {
                                rowPanel(entry, snapshot: snapshot, statuses: statuses)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rowPanel(
        _ entry: PackageEntry, snapshot: PackagesSnapshot, statuses: [PackageTarget: [String: PackageStatus]]
    ) -> some View {
        let fitting = snapshot.targets.filter { target in
            PackageBatch.fits(
                entry, on: target, platform: snapshot.platform(of: target),
                status: statuses[target]?[entry.name] ?? .available)
        }
        return VStack(alignment: .leading, spacing: m.space.md) {
            if fitting.isEmpty {
                Text(verbatim: "No machine or workspace here can take this package.")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
            } else {
                Text(verbatim: "Choose where, then install or remove.")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                PackageDestinationChips(
                    targets: fitting,
                    installed: Self.installedTargets(of: [entry.name], among: fitting, statuses: statuses),
                    chosen: $page.rowDestinations)
            }
            HStack(spacing: m.space.sm) {
                actionButtons(packages: [entry.name], destinations: page.rowDestinations, snapshot: snapshot, fromRow: true)
                if entry.isLocal, let folder = Self.localFolder(configDirectory: snapshot.configDirectory, name: entry.name) {
                    DMButton("Open folder", systemImage: "folder", variant: .ghost, size: .small) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
                    }
                }
                Spacer(minLength: 0)
                DMButton("Close", variant: .ghost, size: .small) { page.closeRow() }
            }
        }
        .padding(.leading, m.pt(34))
        .padding(.trailing, m.row.horizontal)
        .padding(.bottom, m.space.md)
    }

    private func bulkBar(_ snapshot: PackagesSnapshot, statuses: [PackageTarget: [String: PackageStatus]]) -> some View {
        let names = page.selection.sorted()
        return VStack(alignment: .leading, spacing: m.space.md) {
            HStack(spacing: m.space.md) {
                Text(verbatim: "\(names.count) selected: \(names.joined(separator: ", "))")
                    .font(.dm(12, weight: .medium))
                    .foregroundStyle(Color.dmRowText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: m.space.md)
                DMButton("Clear", variant: .ghost, size: .small) { page.clearSelection() }
            }
            PackageDestinationChips(
                targets: snapshot.targets,
                installed: Self.installedTargets(of: names, among: snapshot.targets, statuses: statuses),
                chosen: $page.bulkDestinations)
            HStack(spacing: m.space.sm) {
                actionButtons(packages: names, destinations: page.bulkDestinations, snapshot: snapshot, fromRow: false)
                Spacer(minLength: 0)
            }
        }
        .padding(m.space.md)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }

    @ViewBuilder
    private func actionButtons(
        packages: [String], destinations: Set<PackageTarget>, snapshot: PackagesSnapshot, fromRow: Bool
    ) -> some View {
        let chosen = snapshot.targets.filter { destinations.contains($0) }
        let install = Self.plan(packages, on: chosen, .install, snapshot: snapshot)
        let remove = Self.plan(packages, on: chosen, .remove, snapshot: snapshot)
        DMButton(Self.buttonTitle(.install, batch: install), systemImage: "arrow.down.circle", variant: .primary,
                 size: .small, isLoading: store.applying) {
            pending = PackagesPendingAction(action: .install, batch: install, fromRow: fromRow)
        }
        .disabled(install.isEmpty || store.applying)
        DMButton(Self.buttonTitle(.remove, batch: remove), systemImage: "minus.circle", variant: .dangerOutline,
                 size: .small) {
            pending = PackagesPendingAction(action: .remove, batch: remove, fromRow: fromRow)
        }
        .disabled(remove.isEmpty || store.applying)
    }

    @ViewBuilder
    private func pendingSyncLine(_ snapshot: PackagesSnapshot, statuses: [PackageTarget: [String: PackageStatus]]) -> some View {
        let waiting = snapshot.targets.filter { target in
            PackagePending.syncRequest(statuses: statuses[target] ?? [:], target: target) != nil
        }
        let machines = Array(Set(waiting.map(\.syncMachine))).sorted()
        if !machines.isEmpty {
            HStack(spacing: m.space.md) {
                Text(verbatim: "Some packages wait for a sync on \(machines.joined(separator: ", ")).")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMButton("Sync now", variant: .outline, size: .small) {
                    for target in waiting { store.syncPending(on: target) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func newPackagePicker(configDirectory: String?) -> some View {
        let settings = AppModel.shared?.settings ?? .empty
        let harnesses = harnessFacade.launchOptions(for: settings, on: .thisMac).filter { $0.choice != .terminal }
        return VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: "Create a package with")
                .font(.dm(12, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            Text(verbatim: "Opens a session on this Mac in your devmachine configuration folder.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(harnesses) { option in
                DMButton(option.title, variant: .outline, size: .small, fillsWidth: true) {
                    startNewPackage(option.choice, configDirectory: configDirectory)
                }
            }
            DMButton("Terminal only", variant: .ghost, size: .small, fillsWidth: true) {
                startNewPackage(.terminal, configDirectory: configDirectory)
            }
        }
        .padding(m.space.lg)
        .frame(width: m.pt(260), alignment: .leading)
        .environment(\.colorScheme, .dark)
    }

    private func startNewPackage(_ choice: SessionLaunchChoice, configDirectory: String?) {
        choosingHarness = false
        let folder = Self.expandingTilde(configDirectory ?? "~/.config/devmachine")
        let startup = Self.newPackageStartup(choice, command: harnessFacade.startupCommand(for: choice))
        AppModel.shared?.openLocalSession(at: folder, startup: startup)
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

    // MARK: - Logic the tests read

    static func narrowed(_ filter: PackageFilter, scope: String?) -> PackageFilter {
        var result = filter
        result.scope = scope
        return result
    }

    static let newPackagePrompt = "I want to create a new devmachine-cli package"

    static func newPackageStartup(_ choice: SessionLaunchChoice, command: String?) -> SessionStartup {
        .asking(newPackagePrompt, with: choice, command: command)
    }

    static func expandingTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func localFolder(configDirectory: String?, name: String) -> String? {
        configDirectory.map { expandingTilde($0) + "/packages/" + name }
    }

    static func statuses(_ snapshot: PackagesSnapshot) -> [PackageTarget: [String: PackageStatus]] {
        Dictionary(uniqueKeysWithValues: snapshot.targets.map { ($0, snapshot.statuses(for: $0)) })
    }

    /// The Installed tab's answer for the dropdowns' machine and workspace:
    /// installed on any of them. None picked keeps the CLI's own list.
    static func installedAnywhere(
        on focus: [PackageTarget], statuses: [PackageTarget: [String: PackageStatus]]
    ) -> [String: PackageStatus]? {
        guard !focus.isEmpty else { return nil }
        var result: [String: PackageStatus] = [:]
        for target in focus {
            for (name, status) in statuses[target] ?? [:] where status.isInstalled { result[name] = .applied }
        }
        return result
    }

    /// The targets that already have every one of `packages`.
    static func installedTargets(
        of packages: [String], among targets: [PackageTarget], statuses: [PackageTarget: [String: PackageStatus]]
    ) -> Set<PackageTarget> {
        Set(targets.filter { target in
            packages.allSatisfy { name in
                switch statuses[target]?[name] ?? .available {
                case .applied, .pendingInstall, .appliedAsDependency: return true
                case .available, .pendingRemove: return false
                }
            }
        })
    }

    static func plan(_ packages: [String], on targets: [PackageTarget], _ action: PackageAction,
                     snapshot: PackagesSnapshot) -> PackageBatch {
        PackageBatch.plan(
            packages: packages, targets: targets, action: action, entries: snapshot.entries,
            statuses: { snapshot.statuses(for: $0) }, platform: { snapshot.platform(of: $0) })
    }

    static func buttonTitle(_ action: PackageAction, batch: PackageBatch) -> String {
        let verb = action == .install ? "Install" : "Remove"
        let count = batch.edits.count
        return count == 0 ? verb : "\(verb) on \(count) \(count == 1 ? "place" : "places")"
    }

    static func confirmTitle(_ action: PackageAction) -> String {
        action == .install ? "Install these packages?" : "Remove these packages?"
    }

    static func confirmMessage(_ batch: PackageBatch, action: PackageAction) -> String {
        var lines = batch.edits.map { edit in
            let names = action == .install ? edit.changes.adds : edit.changes.removes
            return "\(edit.target.title): \(names.joined(separator: ", "))"
        }
        if !batch.skips.isEmpty {
            lines.append("")
            lines.append("Left out:")
            lines += batch.skips.map { "\($0.package) on \($0.target.name) — \($0.reason)" }
        }
        lines.append("")
        lines.append(action == .install
            ? "Each machine syncs afterwards; the corner card shows it."
            : PackageRow.removalHint)
        return lines.joined(separator: "\n")
    }
}

/// The dropdowns, the tabs, the search and the category chips above the rows.
struct PackagesHeader: View {
    let targets: [PackageTarget]
    @Binding var page: PackagesPageState
    @Binding var filter: PackageFilter
    let categories: [String]
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            HStack(spacing: m.space.lg) {
                DMDropdown(label: "Machine", options: Self.options(targets, scope: "machine", all: "All machines"),
                           selection: $page.machine)
                DMDropdown(label: "Workspace", options: Self.options(targets, scope: "workspace", all: "All workspaces"),
                           selection: $page.workspace)
                DMTabStrip(
                    tabs: PackageTab.allCases, selection: $filter.tab, title: \.title,
                    fontSize: 12, grouped: true)
                    .fixedSize()
                DMSearchField(prompt: "Search packages", text: $filter.query)
                    .padding(.horizontal, m.row.horizontal)
                    .padding(.vertical, m.space.sm)
                    .dmSurface(Color.dmSelection, radius: DMRadius.row)
            }
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
        }
    }

    static func options(_ targets: [PackageTarget], scope: String, all: String) -> [DMDropdown<String?>.Option] {
        [.init(value: nil, title: all)]
            + targets.filter { $0.scope == scope }.map { .init(value: $0.name, title: $0.title) }
    }

    private func toggle(_ category: String) {
        if filter.categories.remove(category) == nil { filter.categories.insert(category) }
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
