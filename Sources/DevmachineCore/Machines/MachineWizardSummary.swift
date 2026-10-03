import Foundation

/// One line of the wizard's live summary: what a choice made so far means.
public struct MachineSummaryRow: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

extension MachineWizard {
    /// The choices so far, in the order they are asked, read from the same
    /// plan that runs, so the summary never says what the commands do not.
    public var summary: [MachineSummaryRow] {
        var rows = [MachineSummaryRow(label: "Machine", value: machineLine)]
        if draft.kind == .server, !draft.trimmedName.isEmpty {
            rows.append(MachineSummaryRow(label: "Login", value: loginLine))
        }
        if draft.kind == .localVM, let size = sizeToCreate {
            rows.append(MachineSummaryRow(label: "Size", value: size.summary))
        }
        rows.append(MachineSummaryRow(label: "Packages", value: packagesLine))
        let workspace = plan.contains { $0.kind == .newWorkspace } ? draft.trimmedWorkspace : "None"
        rows.append(MachineSummaryRow(label: "Workspace", value: workspace))
        if firstRun {
            let agents = SkillAgent.names(SkillAgent.ordered(draft.skillAgents))
            rows.append(MachineSummaryRow(
                label: "Coding agents", value: agents.isEmpty ? "None" : agents.joined(separator: ", ")))
        } else {
            rows.append(MachineSummaryRow(
                label: "Install now",
                value: draft.sync ? "Yes: devmachine sync at the end" : "No: written to the configuration only"))
        }
        return rows
    }

    /// The commands the run would start with these answers; none before the
    /// machine has a name, since every command names it.
    public var previewCommands: [String] {
        guard !draft.trimmedName.isEmpty else { return [] }
        return plan.filter(\.isCommand).map(\.displayLine)
    }

    private var machineLine: String {
        let name = draft.trimmedName
        guard !name.isEmpty else { return "Not named yet" }
        switch draft.kind {
        case .localVM:
            return "\(name), a Lima machine on this Mac"
        case .server:
            let address = draft.trimmedAddress
            guard !address.isEmpty else { return name }
            let port = draft.trimmedPort == MachineDraft.defaultPort ? "" : ":\(draft.trimmedPort)"
            return "\(name) at \(address)\(port)"
        }
    }

    private var loginLine: String {
        let user = draft.trimmedUser
        switch draft.login {
        case .password:
            return "\(user) with a password, used once to install a key"
        case .key where unattended && draft.keySource == .agent:
            return "\(user) with a key in the SSH agent"
        case .key:
            return draft.trimmedKeyFile.isEmpty ? "\(user) with an SSH key" : "\(user) with \(draft.trimmedKeyFile)"
        }
    }

    private var packagesLine: String {
        let added = plan.compactMap { step -> String? in
            if case let .addPackage(name) = step.kind { return name }
            return nil
        }
        let all = (draft.essentials ? [MachinePackageCatalog.essentials] : []) + added
        return all.isEmpty ? "None" : all.joined(separator: ", ")
    }
}
