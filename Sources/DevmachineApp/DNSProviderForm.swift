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

    static func addAndSaveConfirmation(_ package: String, machine: String, zones: [String]) -> String {
        installConfirmation(package, machine: machine, zones: zones)
            + " Then it syncs \(package) alone on \(machine) and delivers the token."
    }

    static func removeConfirmation(_ package: String, machine: String) -> String {
        "This removes \(package) from \(machine) in your configuration, runs a full sync on \(machine) so the "
            + "lock forgets it, then deletes its token from this Mac. The role files stay under "
            + "/opt/devmachine/roles/\(package); the zones setting stays in config.yml. Both are harmless."
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

/// What the form offers for one provider package.
enum DNSProviderFormAction: Equatable, CaseIterable {
    case addAndSave
    case saveToken
    case pushAgain
    case remove
}

/// One DNS provider package's form: its token, its zones, and the buttons that
/// add it, sync it and remove it. It drives only `DNSSetupStore`.
struct DNSProviderForm: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var setup: DNSSetupStore
    let package: String
    /// The configured domain, offered as the zone to list for Hostinger.
    var domain = ""

    @State private var token = ""
    @State private var zones = ""
    @State private var showsTokenField = false
    @State private var confirmAdd = false
    @State private var confirmSync = false
    @State private var confirmZones = false
    @State private var confirmRemove = false

    /// The buttons for `state`; an old CLI cannot sync, so it cannot push or
    /// remove either.
    static func actions(for state: DNSProviderState, canRunSync: Bool) -> [DNSProviderFormAction] {
        switch state {
        case .notInstalled: [.addAndSave]
        case .notSynced, .tokenMissing, .noZones, .ready:
            canRunSync ? [.saveToken, .pushAgain, .remove] : [.saveToken]
        case .working, .failed: []
        }
    }

    static func canSubmit(token: String, zones: String) -> Bool {
        DNSProviderSetup.secretInput(token) != nil && DNSProviderCatalog.zones(from: zones) != nil
    }

    var body: some View {
        let state = setup.stateOf(package)
        VStack(alignment: .leading, spacing: m.space.md) {
            if let machine = setup.machine {
                content(state, machine: machine)
            }
        }
        .confirmationDialog(
            "Add \(package) to \(setup.machine ?? "")?", isPresented: $confirmAdd, titleVisibility: .visible
        ) {
            Button("Add and save the token") { addAndSave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: addMessage)
        }
        .confirmationDialog(
            "Set the \(package) zones on \(setup.machine ?? "")?", isPresented: $confirmZones,
            titleVisibility: .visible
        ) {
            Button("Save the zones") {
                let value = zones
                Task { await setup.saveZones(package, zones: value) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: DNSSetupContent.zonesConfirmation(
                package, machine: setup.machine ?? "", zones: typedZones))
        }
        .confirmationDialog(
            "Sync \(package) on \(setup.machine ?? "")?", isPresented: $confirmSync, titleVisibility: .visible
        ) {
            Button("Run sync") { setup.sync(package) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: DNSSetupContent.syncConfirmation(package, machine: setup.machine ?? ""))
        }
        .confirmationDialog(
            "Remove \(package) from \(setup.machine ?? "")?", isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { Task { await setup.remove(package) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: DNSSetupContent.removeConfirmation(package, machine: setup.machine ?? ""))
        }
    }

    private var addMessage: String {
        let machine = setup.machine ?? ""
        return setup.canRunSync()
            ? DNSSetupContent.addAndSaveConfirmation(package, machine: machine, zones: typedZones)
            : DNSSetupContent.installConfirmation(package, machine: machine, zones: typedZones)
    }

    @ViewBuilder
    private func content(_ state: DNSProviderState, machine: String) -> some View {
        switch state {
        case .notInstalled:
            tokenField
            zonesHint(machine: machine)
            actionRow(state, machine: machine)
        case .working(let step):
            HStack(spacing: m.space.sm) {
                ProgressView().controlSize(.mini)
                Text(verbatim: DNSSetupContent.title(.working(step), machine: machine, provider: package))
                    .font(.dm(12.5, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
            }
            if step == .sync { paragraph(DNSSetupContent.syncingBody) }
        case let .failed(step, cause, details):
            DMErrorStateView(
                state: DMErrorState(
                    title: DNSSetupContent.title(
                        .failed(step, cause: cause, details: details), machine: machine, provider: package),
                    cause: cause, details: details),
                retry: retry(step),
                retryTitle: step == .sync ? "Run sync again" : "Back")
                .frame(maxWidth: .infinity)
            DMReportBugButton {
                BugReportEnvironment.report(
                    title: "DNS setup failed: \(step)", stepID: "dns-\(step)",
                    command: "devmachine (DNS setup, \(step))", exitCode: nil,
                    lines: details.components(separatedBy: "\n"))
            }
            .frame(maxWidth: .infinity)
        case .notSynced, .tokenMissing, .noZones, .ready:
            installed(state, machine: machine)
        }
    }

    @ViewBuilder
    private func installed(_ state: DNSProviderState, machine: String) -> some View {
        if let problem = Self.problem(state) { paragraph(DNSSetupContent.body(problem, provider: package)) }
        if state == .noZones {
            zonesHint(machine: machine)
            if setup.canEditMachineSettings(), DNSProviderCatalog.zonesSetting(for: package) != nil {
                DMButton("Save the zones", variant: .outline, size: .small) { confirmZones = true }
                    .disabled(typedZones.isEmpty || !zonesAreValid)
            }
        }
        if setup.savedZones == package { saved(DNSSetupContent.zonesSaved) }
        if setup.savedToken == package { saved("Token saved.") }
        if showsTokenField || needsToken(state) && setup.savedToken != package { tokenField }
        actionRow(state, machine: machine)
        if !setup.canRunSync() {
            paragraph(DNSSetupContent.oldCLIBody)
            DMCommandBlock(DNSProviderSetup.manualCommands(
                package: package, credential: setup.secretName(package), machine: machine,
                declared: setup.isDeclared(package)))
        }
    }

    private func actionRow(_ state: DNSProviderState, machine: String) -> some View {
        let actions = Self.actions(for: state, canRunSync: setup.canRunSync())
        return HStack(spacing: m.space.sm) {
            ForEach(actions, id: \.self) { action in
                button(action, state: state)
            }
        }
    }

    @ViewBuilder
    private func button(_ action: DNSProviderFormAction, state: DNSProviderState) -> some View {
        switch action {
        case .addAndSave:
            DMButton("Add \(package)", systemImage: "plus", size: .small) { confirmAdd = true }
                .disabled(!Self.canSubmit(token: token, zones: zones))
        case .saveToken:
            if showsTokenField || needsToken(state) {
                DMButton("Save token", variant: .outline, size: .small) { saveToken() }
                    .disabled(DNSProviderSetup.secretInput(token) == nil)
            } else {
                DMButton("Set or replace the token", variant: .link, size: .small) { showsTokenField = true }
            }
        case .pushAgain:
            DMButton("Push again", systemImage: "arrow.triangle.2.circlepath", size: .small) { confirmSync = true }
        case .remove:
            DMButton("Remove", variant: .danger, size: .small) { confirmRemove = true }
        }
    }

    private static func problem(_ state: DNSProviderState) -> DNSSetupProblem? {
        switch state {
        case .notSynced: .notApplied
        case .tokenMissing(let error): .providerError(error)
        case .noZones: .noZones
        default: nil
        }
    }

    private func needsToken(_ state: DNSProviderState) -> Bool {
        switch state {
        case .tokenMissing, .noZones: true
        default: false
        }
    }

    private func retry(_ step: DNSSetupStep) -> () -> Void {
        guard step == .sync else { return { setup.dismissFailure() } }
        return {
            guard !setup.retrySync() else { return }
            setup.dismissFailure()
            confirmSync = true
        }
    }

    private var tokenField: some View {
        SecureField(DNSSetupContent.tokenPrompt(package), text: $token)
            .dmField()
            .frame(maxWidth: m.pt(360))
    }

    @ViewBuilder
    private func zonesHint(machine: String) -> some View {
        if DNSProviderCatalog.zonesSetting(for: package) != nil {
            let canEdit = setup.canEditMachineSettings()
            VStack(alignment: .leading, spacing: m.space.sm) {
                paragraph(DNSSetupContent.zonesIntro + " "
                    + (canEdit ? DNSSetupContent.zonesApplied : DNSSetupContent.zonesGap))
                TextField(domain.isEmpty ? "example.com" : domain, text: $zones)
                    .dmField()
                    .frame(maxWidth: m.pt(360))
                if !zonesAreValid { paragraph(DNSSetupContent.zonesInvalid) }
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
    private var typedZones: [String] {
        guard setup.canEditMachineSettings(), DNSProviderCatalog.zonesSetting(for: package) != nil else { return [] }
        return DNSProviderCatalog.zones(from: zones) ?? []
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(11.5))
            .foregroundStyle(Color.dmMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func saved(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.dm(11.5))
            .foregroundStyle(Color.dmMuted)
    }

    private func addAndSave() {
        let value = token
        let zoneText = typedZones.joined(separator: ", ")
        token = ""
        Task { await setup.installAndSync(package, token: value, zones: zoneText) }
    }

    private func saveToken() {
        let value = token
        token = ""
        showsTokenField = false
        Task { await setup.saveTokenAndSync(package, token: value) }
    }
}
