import SwiftUI
import DevmachineCore

enum SubdomainMode: String, CaseIterable {
    case managed
    case custom

    func title(baseDomain: String) -> String {
        switch self {
        case .managed: return "\(baseDomain) subdomain"
        case .custom: return "Custom domain"
        }
    }
}

/// Which machines can serve a site (those with caddy) and where each
/// workspace lives: what the form needs to publish through another machine.
struct PublishPlaces: Equatable {
    var servingMachines: [String] = []
    var machineOf: [String: String] = [:]
}

struct AddSubdomainForm {
    let workspaceNames: [String]
    var selectedWorkspace: String
    var mode: SubdomainMode = .managed
    var label = ""
    var customHost = ""
    var port = ""
    /// The workspace's own listening ports, offered as one-tap fills — the
    /// quick-publish flow started from a workspace row.
    var suggestedPorts: [PortSuggestion] = []
    private(set) var places = PublishPlaces()
    private var preferredMachine: String?
    /// The machine whose Caddy serves the site; nil when it is not known,
    /// and then the CLI picks the workspace's own, as it always did.
    var servingMachine: String?

    /// `onMachine` narrows the list to the workspaces on the machine the
    /// Subdomains page shows; nil offers every remote workspace.
    init(
        workspaces: [Workspace], onMachine: [String]? = nil, preselectedWorkspace: String? = nil,
        suggestedPorts: [PortSuggestion] = [], suggestedLabel: String = ""
    ) {
        workspaceNames = workspaces
            .filter { !$0.isLocal && (onMachine?.contains($0.name) ?? true) }
            .map(\.name)
        if let preselectedWorkspace, workspaceNames.contains(preselectedWorkspace) {
            selectedWorkspace = preselectedWorkspace
        } else {
            selectedWorkspace = workspaceNames.first ?? ""
        }
        self.suggestedPorts = suggestedPorts
        label = suggestedLabel
        if let first = suggestedPorts.first {
            port = String(first.port)
        }
    }

    /// Fresh ports arrived while the sheet is open. The port field follows
    /// them only while it still holds the old first suggestion, or nothing:
    /// a port the person typed stays.
    mutating func updateSuggestions(_ fresh: [PortSuggestion]) {
        let untouched = port.isEmpty || port == suggestedPorts.first.map { String($0.port) }
        suggestedPorts = fresh
        if untouched, let first = fresh.first {
            port = String(first.port)
        }
    }

    var workspaceMachine: String? { places.machineOf[selectedWorkspace] }

    var workspaceMachineHasNoCaddy: Bool {
        guard let own = workspaceMachine, !places.servingMachines.isEmpty else { return false }
        return !places.servingMachines.contains(own)
    }

    /// The `--via` to pass: only when another machine serves the site.
    var via: String? {
        guard let servingMachine, let own = workspaceMachine, servingMachine != own else { return nil }
        return servingMachine
    }

    /// `preferring` is the machine the Subdomains page shows: it serves a
    /// workspace whose own machine cannot.
    mutating func update(places: PublishPlaces, preferring: String?) {
        self.places = places
        preferredMachine = preferring
        workspaceChanged()
    }

    mutating func workspaceChanged() {
        let serving = places.servingMachines
        if let own = workspaceMachine, serving.contains(own) {
            servingMachine = own
        } else if let preferredMachine, serving.contains(preferredMachine) {
            servingMachine = preferredMachine
        } else {
            servingMachine = workspaceMachine == nil ? nil : serving.first
        }
    }

    func request(baseDomain: String) -> SubdomainRequest? {
        guard workspaceNames.contains(selectedWorkspace), let portValue = Int(port) else { return nil }
        let candidate: SubdomainRequest
        switch mode {
        case .managed:
            candidate = .subdomain(label: label, port: portValue, baseDomain: baseDomain)
        case .custom:
            candidate = SubdomainRequest(host: customHost, port: portValue, managedDNS: false)
        }
        guard (try? CaddyAdd.validate(candidate)) != nil else { return nil }
        return candidate
    }
}

struct AddSubdomainSheet: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var store: CaddyStore
    @Environment(\.dismiss) private var dismiss

    let settings: AppSettings
    let preferredMachine: String?
    let suggestedPorts: [PortSuggestion]
    let portsAsOf: Date?
    let isRefreshingPorts: Bool
    @State private var form: AddSubdomainForm
    @State private var confirming = false

    init(
        settings: AppSettings, workspaces: [Workspace], onMachine: [String]? = nil,
        preferredMachine: String? = nil, preselectedWorkspace: String? = nil,
        suggestedPorts: [PortSuggestion] = [], suggestedLabel: String = "",
        portsAsOf: Date? = nil, isRefreshingPorts: Bool = false
    ) {
        self.settings = settings
        self.preferredMachine = preferredMachine
        self.suggestedPorts = suggestedPorts
        self.portsAsOf = portsAsOf
        self.isRefreshingPorts = isRefreshingPorts
        _form = State(initialValue: AddSubdomainForm(
            workspaces: workspaces, onMachine: onMachine, preselectedWorkspace: preselectedWorkspace,
            suggestedPorts: suggestedPorts, suggestedLabel: suggestedLabel))
    }

    private var request: SubdomainRequest? {
        form.request(baseDomain: settings.baseDomain)
    }

    private var confirmMessage: String {
        guard let request else { return "Choose a workspace, host and port." }
        if let via = form.via {
            return "Publish \(request.host) from workspace \(form.selectedWorkspace) on port \(request.port) through \(via)? This makes the service public."
        }
        return "Publish \(request.host) from workspace \(form.selectedWorkspace) on port \(request.port)? This makes the service public."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            Text("Add subdomain")
                .font(.dm(14, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            VStack(alignment: .leading, spacing: m.space.sm) {
                Text("Workspace")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                if form.workspaceNames.isEmpty {
                    Text("No visible remote workspace is available.")
                        .font(.dm(11))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Workspace", selection: $form.selectedWorkspace) {
                        ForEach(form.workspaceNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                }
            }

            if form.workspaceMachineHasNoCaddy || form.places.servingMachines.count > 1 {
                servingSection
            }

            Picker("", selection: $form.mode) {
                ForEach(SubdomainMode.allCases, id: \.self) { mode in
                    Text(mode.title(baseDomain: settings.baseDomain)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch form.mode {
            case .managed:
                VStack(alignment: .leading, spacing: m.space.sm) {
                    Text("Label")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                    HStack(spacing: m.space.xs) {
                        TextField("myapp", text: $form.label)
                            .textFieldStyle(.roundedBorder)
                        Text(verbatim: ".\(settings.baseDomain)")
                            .font(.dm(12))
                            .foregroundStyle(Color.dmMuted)
                    }
                }
            case .custom:
                VStack(alignment: .leading, spacing: m.space.sm) {
                    Text("Domain")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                    TextField("app.example.com", text: $form.customHost)
                        .textFieldStyle(.roundedBorder)
                    Text("The CLI manages DNS when a configured provider owns this zone; otherwise it reports the manual record.")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }

            VStack(alignment: .leading, spacing: m.space.sm) {
                HStack(spacing: m.space.sm) {
                    Text("Local port")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                    Spacer(minLength: 0)
                    if isRefreshingPorts {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel(Text(verbatim: "Reading ports"))
                    }
                    DMAgeLabel(since: portsAsOf, staleAfter: CachePolicy.standard.ttl(for: .ports))
                }
                TextField("8080", text: $form.port)
                    .textFieldStyle(.roundedBorder)
                if !form.suggestedPorts.isEmpty {
                    suggestedPortsRow
                }
            }

            HStack {
                Spacer()
                DMButton("Cancel", variant: .outline) { dismiss() }
                DMButton("Create") { confirming = true }
                    .disabled(request == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(m.pt(20))
        .frame(width: m.card.sheetSmall)
        .background(Color.dmContentBg)
        .onChange(of: suggestedPorts) { _, fresh in form.updateSuggestions(fresh) }
        .onChange(of: form.selectedWorkspace) { _, _ in form.workspaceChanged() }
        .onChange(of: store.publishPlaces, initial: true) { _, places in
            form.update(places: places, preferring: preferredMachine)
        }
        .onAppear { store.loadPublishPlacesIfNeeded() }
        .confirmationDialog(
            confirmMessage,
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Create", role: .destructive) {
                if let request {
                    store.addSubdomain(request, workspace: form.selectedWorkspace, via: form.via)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var servingSection: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            Text("Published by")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            if form.places.servingMachines.isEmpty {
                Text("No machine has Caddy yet.")
                    .font(.dm(11))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Published by", selection: $form.servingMachine) {
                    ForEach(form.places.servingMachines, id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                .labelsHidden()
            }
            if let own = form.workspaceMachine, let serving = form.via {
                Text(form.workspaceMachineHasNoCaddy
                     ? "\(own) has no Caddy, so \(serving) serves this site and forwards visitors to \(own) over the address \(own) has in the configuration."
                     : "\(serving) serves this site and forwards visitors to \(own).")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var suggestedPortsRow: some View {
        FlowLayout(spacing: 4, rowSpacing: 4) {
            ForEach(form.suggestedPorts) { suggestion in
                Button {
                    form.port = String(suggestion.port)
                } label: {
                    if let containerName = suggestion.containerName {
                        Text(verbatim: "\(suggestion.port) · \(containerName)")
                    } else {
                        Text(verbatim: "\(suggestion.port)")
                    }
                }
                .buttonStyle(.dmChip)
                .font(.dm(11))
            }
        }
    }
}
