import SwiftUI
import DevmachineCore

/// Settings → Machines: the network map, every machine in the CLI's
/// configuration with what the CLI can do to it, and the way into the Add
/// machine wizard.
struct MachinesSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var caddy: CaddyStore
    @ObservedObject var store: MachinesStore = .shared
    @ObservedObject var details: MachineDetailsStore = .shared
    @ObservedObject var packages: PackagesStore = .shared
    @State private var confirmingRemoval: ConfiguredMachine?
    @State private var confirmingDelete: ConfiguredMachine?
    @State private var selected: String? = DemoSnapshots.machinesSelected

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            HStack {
                Text(verbatim: summary)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                DMButton("Add a machine", systemImage: "plus", size: .small) { model.showPage(.addMachine) }
            }
            content
            if let error = store.removalError {
                DMErrorStateView(state: error, retry: nil)
                DMButton("Dismiss", variant: .ghost, size: .small) { store.removalError = nil }
            }
        }
        .task {
            await store.load()
            caddy.appear()
            packages.requestLoad()
        }
        .confirmationDialog(
            "Remove \(confirmingRemoval?.name ?? "") from the configuration?",
            isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } }),
            presenting: confirmingRemoval
        ) { machine in
            Button("Remove \(machine.name)", role: .destructive) {
                Task { await store.removeMachine(machine.name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { machine in
            Text(verbatim: MachineActions.removeMessage(machine))
        }
        .confirmationDialog(
            "Delete the VM \(confirmingDelete?.name ?? "")?",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            presenting: confirmingDelete
        ) { machine in
            Button("Delete the VM \(machine.name)", role: .destructive) {
                actions.runLocal(.delete, machine: machine.name)
            }
            Button("Cancel", role: .cancel) {}
        } message: { machine in
            Text(verbatim: MachineActions.deleteMessage(machine))
        }
    }

    private var actions: MachineActions { MachineActions(model: model, packages: packages) }

    private var summary: String {
        switch store.machines.count {
        case 0: return "No machine yet."
        case 1: return "1 machine."
        default: return "\(store.machines.count) machines."
        }
    }

    private var map: NetworkMap {
        NetworkMap.build(NetworkMapSource.input(machines: store.machines, sites: caddy.sitesByMachine))
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading where store.snapshot == nil:
            ProgressView().controlSize(.small)
        case let .failed(error) where store.snapshot == nil:
            DMErrorStateView(state: error, retry: { Task { await store.load() } })
        default:
            if store.machines.isEmpty {
                Text(verbatim: "Add a server you already have, or a machine on this Mac to try "
                    + "devmachine without one. Local sessions work either way.")
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: m.space.md) {
                        NetworkMapView(map: map, selected: selected) { name in
                            selected = name
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(name, anchor: .top) }
                        }
                        .padding(.vertical, m.space.sm)
                        .dmSurface(Color.dmBand, radius: DMRadius.panel)
                        ForEach(store.machines) { machine in
                            row(machine).id(machine.name)
                        }
                    }
                }
            }
        }
    }

    private func row(_ machine: ConfiguredMachine) -> some View {
        MachineSettingsRow(
            machine: machine,
            selected: selected == machine.name,
            sites: MachineSites.list(for: machine, machines: store.machines, sites: caddy.sitesByMachine),
            hasPendingSync: actions.pendingSync(machine) != nil,
            takesLocation: store.snapshot?.takesLocation ?? false,
            knownLocations: knownLocations,
            isRemoving: store.removing == machine.name,
            details: details,
            handlers: MachineSettingsRow.Handlers(
                select: { selected = machine.name },
                sync: { actions.sync(machine) },
                fullSync: { actions.fullSync(machine) },
                local: { actions.runLocal($0, machine: machine.name) },
                deleteVM: { confirmingDelete = machine },
                hostKey: { model.showHostKey(machine.name) },
                packages: { model.openPackages(machine: machine.name) },
                remove: { confirmingRemoval = machine }))
    }

    private var knownLocations: [String] {
        var seen = Set<String>()
        return store.machines.map(\.location).filter { seen.insert($0).inserted }
    }
}

/// What a machine's buttons start: syncs and Lima runs go to the corner as
/// machine jobs; nothing here streams into the page.
@MainActor
struct MachineActions {
    let model: AppModel
    let packages: PackagesStore

    func pendingSync(_ machine: ConfiguredMachine) -> SyncRequest? {
        guard let snapshot = packages.snapshot else { return nil }
        let target = PackageTarget.machine(machine.name, isSelf: machine.isSelf)
        return PackagePending.syncRequest(statuses: snapshot.statuses(for: target), target: target)
    }

    /// What the configuration declares and the lock does not have yet.
    func sync(_ machine: ConfiguredMachine) {
        packages.syncPending(on: .machine(machine.name, isSelf: machine.isSelf))
    }

    func fullSync(_ machine: ConfiguredMachine) {
        model.jobs.requestSync(
            SyncRequest(machine: machine.name, full: true, reasons: ["Full sync"]),
            onFinish: { _ in MachinesStore.shared.requestLoad() })
    }

    func runLocal(_ command: LocalMachineCommand, machine: String) {
        model.jobs.run(
            MachineJobPlan(machine: machine, title: command.title(machine: machine),
                           steps: [command.arguments(machine: machine)]),
            onFinish: { _ in
                MachinesStore.shared.requestLoad()
                MachineReadinessStore.shared.requestCheck()
            })
    }

    static func removeMessage(_ machine: ConfiguredMachine) -> String {
        let kept = machine.isLocalVM
            ? "The VM keeps running on this Mac; Delete VM is what destroys it."
            : "The server keeps running and nothing on it changes."
        return "Runs devmachine machines rm \(machine.name). \(kept) This Mac only forgets it."
    }

    static func deleteMessage(_ machine: ConfiguredMachine) -> String {
        "Runs devmachine machines delete-local \(machine.name): the VM and everything on it, its workspaces' "
            + "files included, is destroyed. The configuration still lists \(machine.name) until you Remove it."
    }
}

/// The sites one machine serves, and the ones another machine's Caddy
/// serves for its workspaces (`expose --via`).
enum MachineSites {
    struct Entry: Equatable, Identifiable {
        let host: String
        /// The machine whose Caddy serves it, when that is another one.
        let via: String?
        var id: String { host }
    }

    static func list(
        for machine: ConfiguredMachine, machines: [ConfiguredMachine], sites: [String: MachineSitesState]
    ) -> [Entry] {
        let owner = Dictionary(
            machines.flatMap { machine in machine.workspaces.map { ($0, machine.name) } },
            uniquingKeysWith: { first, _ in first })
        return machines.flatMap { door in
            (sites[door.name]?.rows ?? []).compactMap { row -> Entry? in
                let workspace = row.site.workspace ?? row.resolvedWorkspace
                let target = workspace.flatMap { owner[$0] } ?? door.name
                if door.name == machine.name { return Entry(host: row.site.host, via: nil) }
                return target == machine.name ? Entry(host: row.site.host, via: door.name) : nil
            }
        }
    }
}
