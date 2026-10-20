import SwiftUI
import DevmachineCore

/// The card's words for each state, kept apart from the view so they are
/// tested.
enum DNSSetupContent {
    static func title(_ state: DNSSetupState, machine: String, provider: String?) -> String {
        let name = provider ?? "the provider"
        switch state {
        case .unknown, .ready:
            return ""
        case .noneInstalled:
            return "\(machine) can't create DNS records"
        case .notSynced(let provider, .notApplied):
            return "\(provider) isn't on \(machine) yet"
        case .notSynced(let provider, .providerError):
            return "\(provider) on \(machine) can't reach your DNS yet"
        case .notSynced(let provider, .noZones):
            return "\(provider) on \(machine) sees no domain"
        case .working(.install):
            return "Adding \(name) to \(machine)…"
        case .working(.saveZones):
            return "Saving the \(name) zones…"
        case .working(.saveToken):
            return "Saving the \(name) token…"
        case .working(.sync):
            return "Syncing \(name) on \(machine)…"
        case .working(.remove):
            return "Removing \(name) from \(machine)…"
        case .failed(.install, _, _):
            return "\(name) was not added"
        case .failed(.saveZones, _, _):
            return "The \(name) zones were not saved"
        case .failed(.saveToken, _, _):
            return "The \(name) token was not saved"
        case .failed(.sync, _, _):
            return "The sync of \(name) failed"
        case .failed(.remove, _, _):
            return "\(name) was not removed"
        }
    }

    static let handMadeRecords = "Until then, publishing a port saves the site and only prints the DNS "
        + "record for you to create by hand."

    static let noneInstalledBody = "No DNS provider is installed here, so publishing a port only prints the "
        + "DNS record for you to create by hand. Pick yours and paste its API token: new subdomains then get "
        + "their record on their own."

    static func body(_ problem: DNSSetupProblem, provider: String) -> String {
        switch problem {
        case .notApplied:
            return "It is in the configuration, but no sync has put it on the machine. Run sync to "
                + "apply \(provider) alone and deliver its token. " + handMadeRecords
        case .providerError(let message):
            return "It answered: \(message). Most often its token never reached the machine: save it "
                + "again if needed, then run sync. " + handMadeRecords
        case .noZones:
            if DNSProviderCatalog.zonesSetting(for: provider) != nil {
                return "The token works but lists no domain. A Hostinger token with DNS permission and "
                    + "without Domains portfolio permission sees no zone unless the machine lists them."
            }
            return "The token works but can see no zone. Give it access to your domain, save it, and run sync."
        }
    }

    static let zonesIntro = "Optional: the domains this token may manage, when it lacks Domains portfolio "
        + "permission, separated by commas."

    static let zonesApplied = "They go into this machine's settings in your devmachine configuration; "
        + "sync applies them."

    static let zonesGap = "Your devmachine CLI can't set a machine setting (it needs "
        + "\(DNSProviderSetup.machineSettingsMinimumCLIVersion) or newer), so add this to config.yml in "
        + "the CLI's configuration folder, then run sync."

    static let zonesInvalid = "Only domain names, separated by commas."

    static let zonesSaved = "Zones saved. Run sync to apply them."

    static let noCatalog = "The packages release offers no DNS provider package. Check what it has with:"

    static let syncingBody = "The card in the corner shows its log."

    static let oldCLIBody = "Your devmachine CLI can't sync one package from here (it needs "
        + "\(MachinePrepare.minimumCLIVersion) or newer). Update it, or run this in a terminal:"

    static func installConfirmation(_ package: String, machine: String, zones: [String] = []) -> String {
        let setting = zones.isEmpty ? "" : ", sets the zones it may manage to \(zones.joined(separator: ", "))"
        return "This adds \(package) to \(machine) in your devmachine configuration\(setting) and stores its "
            + "token in the CLI's secret store, all on this Mac. The machine changes only when you run sync."
    }

    static func zonesConfirmation(_ package: String, machine: String, zones: [String]) -> String {
        "This sets the zones \(package) may manage on \(machine) to \(zones.joined(separator: ", ")), in your "
            + "devmachine configuration on this Mac. The machine changes only when you run sync."
    }

    static func syncConfirmation(_ package: String, machine: String) -> String {
        "This applies the \(package) package on \(machine), then delivers its token with credentials "
            + "push. Nothing else waiting in the configuration is applied."
    }

    static func tokenPrompt(_ package: String) -> String {
        "\(package) API token"
    }
}

/// What the Subdomains page says while the selected server has no DNS
/// provider that answers: pick one, add it with its token, sync it. It stays
/// until `dns providers` answers with a zone.
struct DNSProviderSetupCard: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var setup: DNSSetupStore
    /// The configured domain, offered as the zone to list for Hostinger.
    var domain = ""

    @State private var chosen: String?
    @State private var token = ""
    @State private var zones = ""
    @State private var showsTokenField = false
    @State private var confirmInstall: String?
    @State private var confirmSync: String?
    @State private var confirmZones: String?

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
            .confirmationDialog(
                confirmInstall.map { "Add \($0) to \(machine)?" } ?? "",
                isPresented: Binding(get: { confirmInstall != nil }, set: { if !$0 { confirmInstall = nil } }),
                titleVisibility: .visible
            ) {
                Button("Add and save the token") {
                    if let package = confirmInstall { install(package) }
                    confirmInstall = nil
                }
                Button("Cancel", role: .cancel) { confirmInstall = nil }
            } message: {
                Text(verbatim: DNSSetupContent.installConfirmation(
                    confirmInstall ?? "", machine: machine, zones: confirmInstall.map(typedZones) ?? []))
            }
            .confirmationDialog(
                confirmZones.map { "Set the \($0) zones on \(machine)?" } ?? "",
                isPresented: Binding(get: { confirmZones != nil }, set: { if !$0 { confirmZones = nil } }),
                titleVisibility: .visible
            ) {
                Button("Save the zones") {
                    if let package = confirmZones {
                        let value = zones
                        Task { await setup.saveZones(package, zones: value) }
                    }
                    confirmZones = nil
                }
                Button("Cancel", role: .cancel) { confirmZones = nil }
            } message: {
                Text(verbatim: DNSSetupContent.zonesConfirmation(
                    confirmZones ?? "", machine: machine, zones: confirmZones.map(typedZones) ?? []))
            }
            .confirmationDialog(
                confirmSync.map { "Sync \($0) on \(machine)?" } ?? "",
                isPresented: Binding(get: { confirmSync != nil }, set: { if !$0 { confirmSync = nil } }),
                titleVisibility: .visible
            ) {
                Button("Run sync") {
                    if let package = confirmSync { setup.sync(package) }
                    confirmSync = nil
                }
                Button("Cancel", role: .cancel) { confirmSync = nil }
            } message: {
                Text(verbatim: DNSSetupContent.syncConfirmation(confirmSync ?? "", machine: machine))
            }
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
        switch setup.state {
        case .noneInstalled:
            noneInstalled(machine)
        case let .notSynced(provider, problem):
            notSynced(provider, problem: problem, machine: machine)
        case .working(.sync):
            paragraph(DNSSetupContent.syncingBody)
        case .working:
            EmptyView()
        case let .failed(step, cause, details):
            DMErrorStateView(
                state: DMErrorState(
                    title: DNSSetupContent.title(setup.state, machine: machine, provider: provider),
                    cause: cause, details: details),
                retry: retry(step),
                retryTitle: step == .sync ? "Run sync again" : "Back")
                .frame(maxWidth: .infinity)
            DMReportBugButton {
                BugReportEnvironment.report(
                    title: "DNS setup failed: \(step)", stepID: "dns-\(step)", command: "devmachine (DNS setup, \(step))",
                    exitCode: nil, lines: details.components(separatedBy: "\n"))
            }
            .frame(maxWidth: .infinity)
        case .unknown, .ready:
            EmptyView()
        }
    }

    private func retry(_ step: DNSSetupStep) -> () -> Void {
        guard step == .sync, let provider else { return { setup.dismissFailure() } }
        return {
            guard !setup.retrySync() else { return }
            setup.dismissFailure()
            confirmSync = provider
        }
    }

    @ViewBuilder
    private func noneInstalled(_ machine: String) -> some View {
        paragraph(DNSSetupContent.noneInstalledBody)
        if setup.catalog.isEmpty {
            paragraph(DNSSetupContent.noCatalog)
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
                tokenField(package)
                zonesHint(package, machine: machine)
                DMButton("Add \(package)", systemImage: "plus", size: .small) {
                    confirmInstall = package
                }
                .disabled(DNSProviderSetup.secretInput(token) == nil || !zonesAreValid)
            }
        }
    }

    @ViewBuilder
    private func notSynced(_ provider: String, problem: DNSSetupProblem, machine: String) -> some View {
        paragraph(DNSSetupContent.body(problem, provider: provider))
        if problem == .noZones {
            zonesHint(provider, machine: machine)
            if setup.canEditMachineSettings(), DNSProviderCatalog.zonesSetting(for: provider) != nil {
                DMButton("Save the zones", variant: .outline, size: .small) { confirmZones = provider }
                    .disabled(typedZones(provider).isEmpty || !zonesAreValid)
            }
        }
        if setup.savedZones == provider {
            Label(DNSSetupContent.zonesSaved, systemImage: "checkmark.circle.fill")
                .font(.dm(11.5))
                .foregroundStyle(Color.dmMuted)
        }
        if setup.savedToken == provider {
            Label("Token saved. Run sync to deliver it.", systemImage: "checkmark.circle.fill")
                .font(.dm(11.5))
                .foregroundStyle(Color.dmMuted)
        }
        if showsTokenField || problem != .notApplied && setup.savedToken != provider {
            tokenField(provider)
            DMButton("Save token", variant: .outline, size: .small) {
                save(provider)
            }
            .disabled(DNSProviderSetup.secretInput(token) == nil)
        }
        if setup.canRunSync() {
            HStack(spacing: m.space.sm) {
                DMButton("Run sync", systemImage: "arrow.triangle.2.circlepath", size: .small) {
                    confirmSync = provider
                }
                if !showsTokenField, problem == .notApplied {
                    DMButton("Set or replace the token", variant: .link, size: .small) { showsTokenField = true }
                }
            }
        } else {
            paragraph(DNSSetupContent.oldCLIBody)
            DMCommandBlock(DNSProviderSetup.manualCommands(
                package: provider, credential: setup.secretName(provider), machine: machine,
                declared: setup.isDeclared(provider)))
        }
    }

    private func tokenField(_ package: String) -> some View {
        SecureField(DNSSetupContent.tokenPrompt(package), text: $token)
            .dmField()
            .frame(maxWidth: m.pt(360))
    }

    @ViewBuilder
    private func zonesHint(_ package: String, machine: String) -> some View {
        if DNSProviderCatalog.zonesSetting(for: package) != nil {
            let canEdit = setup.canEditMachineSettings()
            VStack(alignment: .leading, spacing: m.space.sm) {
                paragraph(DNSSetupContent.zonesIntro + " "
                    + (canEdit ? DNSSetupContent.zonesApplied : DNSSetupContent.zonesGap))
                TextField(domain.isEmpty ? "example.com" : domain, text: $zones)
                    .dmField()
                    .frame(maxWidth: m.pt(360))
                if !zonesAreValid {
                    paragraph(DNSSetupContent.zonesInvalid)
                }
                if !canEdit, let snippet = DNSProviderCatalog.zonesSnippet(
                    package: package, machine: machine, zones: zones.isEmpty ? domain : zones) {
                    DMCommandBlock(snippet.components(separatedBy: "\n"))
                }
            }
        }
    }

    private var zonesAreValid: Bool {
        DNSProviderCatalog.zones(from: zones) != nil
    }

    /// What the CLI will be asked to set: nothing when it cannot, or the
    /// package has no zones setting.
    private func typedZones(_ package: String) -> [String] {
        guard setup.canEditMachineSettings(), DNSProviderCatalog.zonesSetting(for: package) != nil else { return [] }
        return DNSProviderCatalog.zones(from: zones) ?? []
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(11.5))
            .foregroundStyle(Color.dmMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func install(_ package: String) {
        let value = token
        let zoneText = typedZones(package).joined(separator: ", ")
        token = ""
        Task { await setup.install(package, token: value, zones: zoneText) }
    }

    private func save(_ package: String) {
        let value = token
        token = ""
        showsTokenField = false
        Task { await setup.saveToken(package, token: value) }
    }
}
