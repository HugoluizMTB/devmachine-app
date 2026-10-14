import SwiftUI
import DevmachineCore

/// One package on the Packages page. The checkbox adds it to the selection
/// the bar at the bottom acts on; a click anywhere else opens the row on
/// what to do with this one package. The pills say where it is now.
struct PackageRow: View {
    let entry: PackageEntry
    let placements: [PackagePlacement]
    let isSelected: Bool
    let isExpanded: Bool
    /// "Linux only" when the picked machine or workspace runs another system.
    var systemFit: PackageSystemFit = .fits
    let toggleSelected: () -> Void
    let toggleExpanded: () -> Void
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(alignment: .top, spacing: m.space.md) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggleSelected() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!systemFit.canTick && !isSelected)
                .help(Text(verbatim: systemFit.canTick
                    ? "Select to act on several packages at once"
                    : "\(systemFit.label ?? ""): it does not run on this machine"))
            VStack(alignment: .leading, spacing: m.space.xs) {
                HStack(spacing: m.space.sm) {
                    Text(verbatim: entry.name)
                        .font(.dm(13, weight: .semibold))
                        .foregroundStyle(systemFit == .fits ? Color.dmRowText : Color.dmMuted)
                    DMKindLabel(text: entry.categoryTitle)
                    DMKindLabel(text: entry.scope)
                    if entry.isLocal { DMKindLabel(text: "local") }
                    if let label = systemFit.label {
                        DMPill(text: label, color: .orange)
                            .help(Text(verbatim: "It does not run on this machine's system, so it is not offered here."))
                    }
                }
                if !entry.summary.isEmpty {
                    Text(verbatim: entry.summary)
                        .font(.dm(11.5))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !entry.credentialNames.isEmpty {
                    HStack(spacing: m.space.xs) {
                        Text(verbatim: "Needs \(entry.credentialNames.joined(separator: ", ")) — set with")
                        Text(verbatim: "devmachine secrets set")
                            .font(.dm(11, design: .monospaced))
                    }
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                }
                if !entry.needs.isEmpty {
                    Text(verbatim: "Brings \(entry.needs.joined(separator: ", "))")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }
            Spacer(minLength: m.space.md)
            FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                ForEach(placements, id: \.target) { placement in
                    DMPill(text: Self.pillText(placement), color: Self.color(for: placement.status))
                }
            }
            .frame(maxWidth: m.pt(320), alignment: .trailing)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.dm(10, weight: .semibold))
                .foregroundStyle(Color.dmMuted)
        }
        .padding(.horizontal, m.row.horizontal)
        .padding(.vertical, m.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleExpanded)
    }

    static func pillText(_ placement: PackagePlacement) -> String {
        let name = placement.target.name
        switch placement.status {
        case .applied, .available: return name
        case let .appliedAsDependency(parent): return "\(name) · via \(parent)"
        case .pendingInstall: return "\(name) · pending install"
        case .pendingRemove: return "\(name) · pending removal"
        }
    }

    static func color(for status: PackageStatus) -> Color {
        switch status {
        case .applied: return .green
        case .pendingInstall, .pendingRemove: return .orange
        case .appliedAsDependency, .available: return .dmMuted
        }
    }

    static let removalHint = "devmachine stops installing and updating it there. It does not uninstall what is already on the machine."
}

/// Where a package is now: one machine or workspace and its status there.
struct PackagePlacement: Equatable {
    let target: PackageTarget
    let status: PackageStatus

    /// Every machine and workspace that has the package, or waits for a sync
    /// to add or drop it, among `targets`.
    static func list(for entry: PackageEntry, targets: [PackageTarget], statuses: [PackageTarget: [String: PackageStatus]])
        -> [PackagePlacement] {
        targets.compactMap { target in
            let status = statuses[target]?[entry.name] ?? .available
            return status == .available ? nil : PackagePlacement(target: target, status: status)
        }
    }
}

/// The machines and workspaces an action goes to, as chips: one group for
/// machines, one for workspaces. A green dot marks one that has every
/// package already.
struct PackageDestinationChips: View {
    let targets: [PackageTarget]
    let installed: Set<PackageTarget>
    @Binding var chosen: Set<PackageTarget>
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            group("Machines", targets.filter { $0.scope == "machine" })
            group("Workspaces", targets.filter { $0.scope == "workspace" })
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [PackageTarget]) -> some View {
        if !items.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: m.space.md) {
                Text(verbatim: title)
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                    .frame(width: m.pt(80), alignment: .leading)
                FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                    ForEach(items, id: \.self) { target in
                        Button {
                            if chosen.remove(target) == nil { chosen.insert(target) }
                        } label: {
                            HStack(spacing: m.space.xs) {
                                Image(systemName: chosen.contains(target) ? "checkmark.circle.fill" : "circle")
                                    .font(.dm(10))
                                    .foregroundStyle(chosen.contains(target) ? Color.accentColor : Color.dmMuted)
                                if installed.contains(target) {
                                    Circle().fill(Color.green).frame(width: m.pt(6), height: m.pt(6))
                                }
                                Text(verbatim: target.name).font(.dm(11.5))
                            }
                        }
                        .buttonStyle(.dmChip(selected: chosen.contains(target)))
                        .help(Text(verbatim: installed.contains(target) ? "Already there" : target.title))
                    }
                }
            }
        }
    }
}
