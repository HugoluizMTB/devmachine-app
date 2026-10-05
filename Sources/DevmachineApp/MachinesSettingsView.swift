import SwiftUI
import DevmachineCore

/// Settings → Machines: every machine in the CLI's configuration, with the
/// actions the CLI has for one, and the way into the Add machine wizard.
struct MachinesSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: MachinesStore = .shared
    @State private var confirmingRemoval: ConfiguredMachine?

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
        .task { await store.load() }
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
            Text(verbatim: "Runs devmachine machines rm \(machine.name). The server keeps running "
                + "and nothing on it changes; this Mac only forgets it.")
        }
    }

    private var summary: String {
        switch store.machines.count {
        case 0: return "No machine yet."
        case 1: return "1 machine."
        default: return "\(store.machines.count) machines."
        }
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
                VStack(alignment: .leading, spacing: m.space.md) {
                    ForEach(store.machines) { machine in
                        MachineSettingsRow(
                            machine: machine,
                            isRemoving: store.removing == machine.name,
                            checkHostKey: { model.showPage(.hostKey(machine.name)) },
                            remove: { confirmingRemoval = machine })
                    }
                }
            }
        }
    }
}

private struct MachineSettingsRow: View {
    @Environment(\.dmMetrics) private var m
    let machine: ConfiguredMachine
    let isRemoving: Bool
    let checkHostKey: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            HStack(spacing: m.space.sm) {
                Text(verbatim: machine.name)
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                if machine.isSelf { DMKindLabel(text: "THIS MAC") }
                Spacer()
                if !machine.isSelf {
                    DMButton("Host key", systemImage: "key", variant: .ghost, size: .small, action: checkHostKey)
                }
                DMButton("Remove…", variant: .ghostDanger, size: .small, isLoading: isRemoving, action: remove)
                    .disabled(!machine.workspaces.isEmpty)
                    .help(machine.workspaces.isEmpty ? "" : "Move or remove its workspaces first.")
            }
            if !machine.isSelf {
                Text(verbatim: MachineSettingsRow.address(machine))
                    .font(.dm(11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .textSelection(.enabled)
            }
            line("Workspaces", machine.workspaces)
            line("Packages", machine.packages)
        }
        .padding(m.space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(Color.white.opacity(0.05), radius: DMRadius.panel)
    }

    private func line(_ title: String, _ values: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
            Text(verbatim: title)
                .font(.dm(11))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: m.pt(78), alignment: .leading)
            if values.isEmpty {
                Text(verbatim: "none")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                    ForEach(values, id: \.self) { DMKindLabel(text: $0) }
                }
            }
        }
    }

    static func address(_ machine: ConfiguredMachine) -> String {
        let hosts = machine.hosts.isEmpty ? "no address" : machine.hosts.joined(separator: ", ")
        return "\(machine.adminUser)@\(hosts) · port \(machine.port)"
    }
}
