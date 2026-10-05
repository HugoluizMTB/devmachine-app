import SwiftUI
import DevmachineCore

/// One package on the Packages page. With a target the checkbox shows what
/// the target will have once the selection is applied, and the pill what it
/// has now; without one, the pills name every machine and workspace with it.
struct PackageRow: View {
    let entry: PackageEntry
    let target: PackageTarget?
    let status: PackageStatus?
    let isSelected: Bool
    let toggle: () -> Void
    @Environment(\.dmMetrics) private var m

    private var block: PackageBlock? { Self.block(entry: entry, status: status, target: target) }

    static func block(entry: PackageEntry, status: PackageStatus?, target: PackageTarget?) -> PackageBlock? {
        guard let target else { return nil }
        return PackageAvailability.block(entry: entry, status: status ?? .available, target: target)
    }

    /// Ticked means "on the target once applied": a ticked row in the
    /// selection flips what the target has now.
    static func isChecked(status: PackageStatus?, isSelected: Bool) -> Bool {
        let declared: Bool
        switch status ?? .available {
        case .applied, .pendingInstall, .appliedAsDependency: declared = true
        case .available, .pendingRemove: declared = false
        }
        return declared != isSelected
    }

    static let removalHint = "Stops being managed; the software stays on the machine."

    static func removalNote(status: PackageStatus?, isSelected: Bool) -> String? {
        isSelected && status == .applied ? removalHint : nil
    }

    static func showsCheckbox(target: PackageTarget?) -> Bool { target != nil }

    static func isDisabled(target: PackageTarget?, block: PackageBlock?) -> Bool {
        target == nil || block != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: m.space.md) {
            if Self.showsCheckbox(target: target) {
                Toggle("", isOn: Binding(get: { Self.isChecked(status: status, isSelected: isSelected) }, set: { _ in toggle() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(Self.isDisabled(target: target, block: block))
                    .help(Text(verbatim: help))
            }
            VStack(alignment: .leading, spacing: m.space.xs) {
                HStack(spacing: m.space.sm) {
                    Text(verbatim: entry.name)
                        .font(.dm(13, weight: .semibold))
                        .foregroundStyle(Color.dmRowText)
                    DMKindLabel(text: entry.categoryTitle)
                    DMKindLabel(text: entry.scope)
                    if entry.isLocal { DMKindLabel(text: "local") }
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
                if let note = Self.removalNote(status: status, isSelected: isSelected) {
                    Text(verbatim: note)
                        .font(.dm(11))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !entry.needs.isEmpty {
                    Text(verbatim: "Brings \(entry.needs.joined(separator: ", "))")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }
            Spacer(minLength: m.space.md)
            pills
        }
        .padding(.horizontal, m.row.horizontal)
        .padding(.vertical, m.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var help: String {
        if let block { return block.message }
        return target == nil ? "Choose a machine or workspace first." : ""
    }

    @ViewBuilder
    private var pills: some View {
        if target != nil {
            if let pill = Self.pill(for: status ?? .available) {
                DMPill(text: pill.text, color: pill.color)
            }
        } else {
            HStack(spacing: m.space.xs) {
                ForEach(entry.installedOn, id: \.self) { label in
                    DMPill(text: Self.shortLabel(label), color: .dmMuted)
                }
            }
        }
    }

    static func pill(for status: PackageStatus) -> (text: String, color: Color)? {
        switch status {
        case .applied: return ("Installed", .green)
        case let .appliedAsDependency(parent): return ("Via \(parent)", .dmMuted)
        case .pendingInstall: return ("Pending install", .orange)
        case .pendingRemove: return ("Pending removal", .orange)
        case .available: return nil
        }
    }

    /// `installed_on` says "machine main"; beside a package the name is enough.
    static func shortLabel(_ label: String) -> String {
        for prefix in ["machine ", "workspace "] where label.hasPrefix(prefix) {
            return String(label.dropFirst(prefix.count))
        }
        return label
    }
}
