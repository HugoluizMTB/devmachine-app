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
    @EnvironmentObject var store: CaddyStore
    @Environment(\.dismiss) private var dismiss

    let settings: AppSettings
    @State private var form: AddSubdomainForm
    @State private var confirming = false

    init(
        settings: AppSettings, workspaces: [Workspace], onMachine: [String]? = nil,
        preselectedWorkspace: String? = nil,
        suggestedPorts: [PortSuggestion] = [], suggestedLabel: String = ""
    ) {
        self.settings = settings
        _form = State(initialValue: AddSubdomainForm(
            workspaces: workspaces, onMachine: onMachine, preselectedWorkspace: preselectedWorkspace,
            suggestedPorts: suggestedPorts, suggestedLabel: suggestedLabel))
    }

    private var request: SubdomainRequest? {
        form.request(baseDomain: settings.baseDomain)
    }

    private var confirmMessage: String {
        guard let request else { return "Choose a workspace, host and port." }
        return "Publish \(request.host) from workspace \(form.selectedWorkspace) on port \(request.port)? This makes the service public."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add subdomain")
                .font(.dm(14, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            VStack(alignment: .leading, spacing: 6) {
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

            Picker("", selection: $form.mode) {
                ForEach(SubdomainMode.allCases, id: \.self) { mode in
                    Text(mode.title(baseDomain: settings.baseDomain)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch form.mode {
            case .managed:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                    HStack(spacing: 4) {
                        TextField("myapp", text: $form.label)
                            .textFieldStyle(.roundedBorder)
                        Text(verbatim: ".\(settings.baseDomain)")
                            .font(.dm(12))
                            .foregroundStyle(Color.dmMuted)
                    }
                }
            case .custom:
                VStack(alignment: .leading, spacing: 6) {
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Local port")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
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
        .padding(20)
        .frame(width: 360)
        .background(Color.dmContentBg)
        .confirmationDialog(
            confirmMessage,
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Create", role: .destructive) {
                if let request {
                    store.addSubdomain(request, workspace: form.selectedWorkspace, settings: settings)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
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
