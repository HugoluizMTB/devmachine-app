import SwiftUI
import DevmachineCore

/// What the Subdomains page says while the selected server has no DNS
/// provider that answers: pick one, add it with its token, sync it. It stays
/// until `dns providers` answers with a zone.
struct DNSProviderSetupCard: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var setup: DNSSetupStore
    /// The configured domain, offered as the zone to list for Hostinger.
    var domain = ""

    @State private var chosen: String?

    var body: some View {
        if setup.state.showsCard, let machine = setup.machine {
            VStack(alignment: .leading, spacing: m.space.md) {
                if !isFailed { header(machine) }
                content(machine)
            }
            .padding(m.space.lg)
            .frame(maxWidth: m.pt(680), alignment: .leading)
            .dmSurface(Color.dmBand, radius: DMRadius.panel)
            .padding(.horizontal, m.pt(14))
            .padding(.bottom, m.space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isFailed: Bool {
        if case .failed = setup.state { return true }
        return false
    }

    private var provider: String? {
        if case .notSynced(let provider, _) = setup.state { return provider }
        return chosen ?? setup.suggestedProvider
    }

    private func header(_ machine: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
            icon
            Text(verbatim: DNSSetupContent.title(setup.state, machine: machine, provider: provider))
                .font(.dm(12.5, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch setup.state {
        case .working:
            ProgressView().controlSize(.mini)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default:
            Image(systemName: "network").foregroundStyle(Color.dmMuted)
        }
    }

    @ViewBuilder
    private func content(_ machine: String) -> some View {
        if case .noneInstalled = setup.state {
            Text(verbatim: DNSSetupContent.noneInstalledBody)
                .font(.dm(11.5))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            if setup.catalog.isEmpty {
                Text(verbatim: DNSSetupContent.noCatalog)
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMCommandBlock("devmachine packages list")
            } else {
                DMTabStrip(
                    tabs: setup.catalog.map(\.name),
                    selection: Binding(
                        get: { provider ?? setup.catalog[0].name },
                        set: { chosen = $0 }),
                    title: { $0 },
                    fontSize: 12,
                    grouped: true)
                if let package = provider {
                    DNSProviderForm(setup: setup, package: package, domain: domain)
                }
            }
        } else if let package = provider {
            DNSProviderForm(setup: setup, package: package, domain: domain)
        }
    }
}
