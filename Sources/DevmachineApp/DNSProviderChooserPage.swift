import SwiftUI
import DevmachineCore

struct DNSProviderCard: Identifiable, Equatable {
    let name: String
    let detail: String
    let systemImage: String
    var id: String { name }
}

/// The full page that says which registrar answers for your domain: one card
/// per provider package, and the form of the chosen one below the cards.
struct DNSProviderChooserPage: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var setup: DNSSetupStore
    var domain = ""
    var initialPackage: String?
    var onBack: (() -> Void)?

    @State private var chosen: String?

    static let title = "Point your domain names from here"
    static let subtitle = "Pick the registrar that holds your domain. Its token lets this machine create a record for every port you publish."

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: m.space.xl) {
                if let onBack {
                    DMButton("Back to Publish", systemImage: "chevron.left", variant: .link, size: .small, action: onBack)
                }
                VStack(alignment: .leading, spacing: m.space.sm) {
                    Text(verbatim: Self.title)
                        .font(.dm(17, weight: .semibold))
                        .foregroundStyle(Color.dmRowText)
                    Text(verbatim: Self.subtitle)
                        .font(.dm(12))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if setup.catalog.isEmpty {
                    Text(verbatim: DNSSetupContent.noCatalog)
                        .font(.dm(11.5))
                        .foregroundStyle(Color.dmMuted)
                    DMCommandBlock("devmachine packages list")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: m.pt(200), maximum: m.pt(300)), spacing: m.space.lg)],
                        alignment: .leading, spacing: m.space.lg
                    ) {
                        ForEach(Self.cards(catalog: setup.catalog)) { card in
                            cardView(card)
                        }
                    }
                    if let package = selected {
                        DNSProviderForm(setup: setup, package: package, domain: domain)
                            .id(package)
                    }
                }
                HStack(spacing: m.space.xs) {
                    Text(verbatim: "You can change this later in")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                    DMButton("Settings → DNS providers", variant: .link, size: .small) {
                        model.openSettings(.dnsProviders)
                    }
                }
            }
            .padding(m.space.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.dmContentBg)
        .onChange(of: setup.machine) { _, _ in chosen = nil }
    }

    private var selected: String? {
        chosen ?? Self.preselected(state: setup.state, initial: initialPackage) ?? busyProvider
    }

    /// A running or failed step names no provider in the state, so the
    /// provider in the configuration stands in for it.
    private var busyProvider: String? {
        switch setup.state {
        case .working, .failed: return setup.suggestedProvider
        default: return nil
        }
    }

    private func cardView(_ card: DNSProviderCard) -> some View {
        DMPictureChoice(
            title: card.name, detail: card.detail, selected: selected == card.name, pictureHeight: 96,
            action: { chosen = card.name }
        ) {
            ZStack {
                Color.dmRowText.opacity(0.08)
                Image(systemName: card.systemImage)
                    .font(.dm(28))
                    .foregroundStyle(Color.dmRowText)
            }
        }
        .demoClickTarget("dns:\(card.name)")
    }

    static func cards(catalog: [CLIPackage]) -> [DNSProviderCard] {
        catalog.map {
            DNSProviderCard(
                name: $0.name, detail: $0.summary ?? "DNS zones on \($0.name).", systemImage: symbol(for: $0.name))
        }
    }

    static func symbol(for package: String) -> String {
        switch package {
        case "cloudflare": return "cloud.fill"
        case "hostinger": return "h.square.fill"
        case "godaddy": return "g.square.fill"
        default: return "globe"
        }
    }

    static func preselected(state: DNSSetupState, initial: String?) -> String? {
        if let initial { return initial }
        if case .notSynced(let provider, _) = state { return provider }
        return nil
    }
}
