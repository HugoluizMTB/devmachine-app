import SwiftUI
import DevmachineCore

struct DNSProviderRow: Identifiable, Equatable {
    let name: String
    let label: String
    var id: String { name }
}

/// Every DNS provider package the release offers, with where it stands on
/// the machine picked above. Opening a row shows the same form as Publish.
struct DNSProvidersSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var caddy: CaddyStore
    @EnvironmentObject private var model: AppModel
    @State private var expanded: String?

    static let noMachine = "No server with Caddy yet. Add one in Machines, then come back here."

    static func rows(catalog: [CLIPackage], stateOf: (String) -> DNSProviderState) -> [DNSProviderRow] {
        catalog.map { DNSProviderRow(name: $0.name, label: stateOf($0.name).label) }
    }

    static func machines(_ all: [CLIMachine]) -> [String] {
        all.filter { !$0.isSelf }.map(\.name)
    }

    static func color(forLabel label: String) -> Color {
        switch label {
        case "Ready": return .green
        case "Not installed": return .dmMuted
        case "Failed": return .red
        default: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            let names = Self.machines(caddy.machines)
            if !names.isEmpty {
                DMTabStrip(
                    tabs: names,
                    selection: Binding(get: { caddy.selectedMachine ?? "" }, set: { caddy.select($0) }),
                    title: { $0 }, fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
                    .fixedSize()
            }
            if caddy.dnsSetup.machine == nil {
                Text(verbatim: Self.noMachine)
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
            } else if caddy.dnsSetup.catalog.isEmpty {
                Text(verbatim: DNSSetupContent.noCatalog)
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMCommandBlock("devmachine packages list")
            } else {
                ForEach(Self.rows(catalog: caddy.dnsSetup.catalog, stateOf: caddy.dnsSetup.stateOf)) { row in
                    VStack(alignment: .leading, spacing: m.space.md) {
                        DMRow(
                            title: row.name,
                            trailing: AnyView(
                                HStack(spacing: m.space.sm) {
                                    DMPill(text: row.label, color: Self.color(forLabel: row.label))
                                    Image(systemName: expanded == row.name ? "chevron.up" : "chevron.down")
                                        .font(.dm(10))
                                        .foregroundStyle(Color.dmMuted)
                                }),
                            tap: { expanded = expanded == row.name ? nil : row.name })
                        if expanded == row.name {
                            DNSProviderForm(setup: caddy.dnsSetup, package: row.name, domain: caddy.domain)
                                .id(row.name)
                                .padding(.leading, m.space.lg)
                        }
                    }
                }
            }
        }
        .task { caddy.appear() }
    }
}
