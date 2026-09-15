import SwiftUI
import DevmachineCore

private enum SubdomainMode: String, CaseIterable {
    case managed
    case custom

    func title(baseDomain: String) -> String {
        switch self {
        case .managed: return "\(baseDomain) subdomain"
        case .custom: return "Custom domain"
        }
    }
}

struct AddSubdomainSheet: View {
    @EnvironmentObject var store: CaddyStore
    @Environment(\.dismiss) private var dismiss

    let settings: AppSettings

    @State private var mode: SubdomainMode = .managed
    @State private var label = ""
    @State private var customHost = ""
    @State private var port = ""
    @State private var confirming = false

    private var req: SubdomainRequest? {
        guard let portValue = Int(port) else { return nil }
        let candidate: SubdomainRequest
        switch mode {
        case .managed:
            candidate = SubdomainRequest.subdomain(
                label: label, port: portValue, baseDomain: settings.baseDomain
            )
        case .custom:
            candidate = SubdomainRequest(host: customHost, port: portValue, managedDNS: false)
        }
        guard (try? CaddyAdd.validate(candidate)) != nil else { return nil }
        return candidate
    }

    private var confirmMessage: String {
        switch mode {
        case .managed:
            return "This creates a live subdomain and public DNS record. Continue?"
        case .custom:
            return "This adds the domain to Caddy and issues TLS. No DNS is created — ensure it already points at the VPS. Continue?"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add subdomain")
                .font(.dm(14, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            Picker("", selection: $mode) {
                ForEach(SubdomainMode.allCases, id: \.self) { mode in
                    Text(mode.title(baseDomain: settings.baseDomain)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .managed:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                    HStack(spacing: 4) {
                        TextField("myapp", text: $label)
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
                    TextField("app.example.com", text: $customHost)
                        .textFieldStyle(.roundedBorder)
                    Text(verbatim: "Point this domain's DNS at \(settings.publicIP) (A record) before creating.")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Local port")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                TextField("8080", text: $port)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { confirming = true }
                    .disabled(req == nil)
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
                if let req {
                    store.addSubdomain(req, settings: settings)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
