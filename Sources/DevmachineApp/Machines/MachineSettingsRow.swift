import SwiftUI
import DevmachineCore

/// One machine in Settings → Machines: what it is and where, what runs on
/// it, and the CLI's actions for it. Reads (Check, Addresses, Credentials)
/// open inline under it; long runs go to the corner.
struct MachineSettingsRow: View {
    struct Handlers {
        let select: () -> Void
        let sync: () -> Void
        let fullSync: () -> Void
        let local: (LocalMachineCommand) -> Void
        let deleteVM: () -> Void
        let hostKey: () -> Void
        let packages: () -> Void
        let remove: () -> Void
    }

    @Environment(\.dmMetrics) private var m
    let machine: ConfiguredMachine
    let selected: Bool
    let sites: [MachineSites.Entry]
    let hasPendingSync: Bool
    let takesLocation: Bool
    let knownLocations: [String]
    let isRemoving: Bool
    @ObservedObject var details: MachineDetailsStore
    let handlers: Handlers
    @State private var editingLocation = false

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            header
            if !machine.isSelf {
                Text(verbatim: Self.address(machine))
                    .font(.dm(11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .textSelection(.enabled)
            }
            systemLine
            locationLine
            line("Workspaces", machine.workspaces)
            sitesLine
            HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
                line("Packages", machine.packages)
                DMButton("Packages on this machine", systemImage: "arrow.right", variant: .link, size: .small,
                         action: handlers.packages)
            }
            if let panel = details.open[machine.name] {
                MachinePanelView(panel: panel, machine: machine, details: details)
            }
        }
        .padding(m.space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(selected ? Color.white.opacity(0.08) : Color.white.opacity(0.05), radius: DMRadius.panel)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: m.radius.panel, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: handlers.select)
    }

    private var header: some View {
        HStack(spacing: m.space.sm) {
            Text(verbatim: machine.name)
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            if machine.isSelf { DMKindLabel(text: "THIS MAC") }
            if machine.isLocalVM { DMKindLabel(text: "LIMA VM") }
            if CaddyDetection.hasCaddy(installedPackageNames: Set(machine.packages)), !machine.isSelf {
                DMKindLabel(text: "CADDY")
            }
            Spacer(minLength: m.space.md)
            panelButton(.check, systemImage: "stethoscope")
            DMButton("Sync", systemImage: "arrow.triangle.2.circlepath", variant: .ghost, size: .small,
                     action: handlers.sync)
                .disabled(!hasPendingSync)
                .help(hasPendingSync ? "Apply what waits in the configuration." : "Nothing waits for a sync.")
            DMButton("Full sync", variant: .ghost, size: .small, action: handlers.fullSync)
                .help("Run every package on the machine again.")
            if machine.isLocalVM {
                DMButton("Start", systemImage: "play", variant: .ghost, size: .small) { handlers.local(.start) }
                DMButton("Stop", systemImage: "stop", variant: .ghost, size: .small) { handlers.local(.stop) }
            }
            moreMenu
        }
    }

    private func panelButton(_ panel: MachineDetailsStore.Panel, systemImage: String) -> some View {
        DMButton(panel.title, systemImage: systemImage,
                 variant: details.open[machine.name] == panel ? .outline : .ghost, size: .small) {
            Task { await details.toggle(panel, machine: machine.name, isSelf: machine.isSelf) }
        }
    }

    private var moreMenu: some View {
        Menu {
            if !machine.isSelf {
                Button("Addresses") {
                    Task { await details.toggle(.addresses, machine: machine.name, isSelf: false) }
                }
                Button("Credentials missing") {
                    Task { await details.toggle(.credentials, machine: machine.name, isSelf: false) }
                }
                Button("SSH password login") {
                    Task { await details.toggle(.passwordLogin, machine: machine.name, isSelf: false) }
                }
                Button("Host key…", action: handlers.hostKey)
            }
            Button("Edit location…") { editingLocation = true }
            Button("Packages on this machine", action: handlers.packages)
            Divider()
            if machine.isLocalVM {
                Button("Delete the VM…", role: .destructive, action: handlers.deleteVM)
            }
            Button("Remove…", role: .destructive, action: handlers.remove)
                .disabled(!machine.workspaces.isEmpty || isRemoving)
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(machine.workspaces.isEmpty ? "More" : "More. Remove needs its workspaces moved or removed first.")
    }

    @ViewBuilder
    private var systemLine: some View {
        if let system = machine.systemLine {
            HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
                label("System")
                Text(verbatim: system)
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
            }
        }
    }

    private var locationLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
            label("Location")
            DMKindLabel(text: machine.location.uppercased())
            DMButton("Edit location", variant: .link, size: .small) { editingLocation = true }
                .popover(isPresented: $editingLocation, arrowEdge: .bottom) {
                    MachineLocationEditor(
                        machine: machine, takesLocation: takesLocation, knownLocations: knownLocations,
                        details: details, done: { editingLocation = false })
                }
        }
    }

    @ViewBuilder
    private var sitesLine: some View {
        if !sites.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
                label("Publish")
                FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                    ForEach(sites) { site in
                        DMKindLabel(text: site.via.map { "\(site.host) via \($0)" } ?? site.host)
                    }
                }
            }
        }
    }

    private func line(_ title: String, _ values: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
            label(title)
            if values.isEmpty {
                Text(verbatim: "none")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                    ForEach(values, id: \.self) { DMKindLabel(text: $0) }
                }
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.dm(11))
            .foregroundStyle(.white.opacity(0.45))
            .frame(width: m.pt(78), alignment: .leading)
    }

    static func address(_ machine: ConfiguredMachine) -> String {
        let hosts = machine.hosts.isEmpty ? "no address" : machine.hosts.joined(separator: ", ")
        return "\(machine.adminUser)@\(hosts) · port \(machine.port)"
    }
}

/// "Edit location": the same field the wizard asks with, then `machines
/// edit --location` on Save. An older CLI keeps no location, so it says so.
struct MachineLocationEditor: View {
    @Environment(\.dmMetrics) private var m
    @Environment(\.dmOpenCLIUpdate) private var openCLIUpdate
    let machine: ConfiguredMachine
    let takesLocation: Bool
    let knownLocations: [String]
    @ObservedObject var details: MachineDetailsStore
    let done: () -> Void
    @State private var location = ""

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: "Where is \(machine.name)?")
                .font(.dm(12, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            if takesLocation {
                MachineLocationField(location: $location, known: knownLocations,
                                     defaultLocation: machine.isLocalVM || machine.isSelf
                                        ? MachineLocation.local : MachineLocation.external)
                if let problem = MachineLocation.problem(location) ?? details.locationError[machine.name] {
                    Text(verbatim: problem)
                        .font(.dm(11))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    DMButton("Cancel", variant: .outline, size: .small, action: done)
                    DMButton("Save", variant: .primary, size: .small,
                             isLoading: details.savingLocation == machine.name) {
                        Task { if await details.saveLocation(location, machine: machine.name) { done() } }
                    }
                    .disabled(MachineLocation.problem(location) != nil)
                }
            } else {
                Text(verbatim: "Your devmachine CLI keeps no location yet. Update it to set one; until then the "
                    + "map puts this machine in \(machine.location).")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    DMButton("Close", variant: .outline, size: .small, action: done)
                    DMButton("Update the CLI", variant: .primary, size: .small) {
                        done()
                        openCLIUpdate?()
                    }
                }
            }
        }
        .padding(m.space.lg)
        .frame(width: m.pt(340))
        .onAppear { location = machine.location }
    }
}

/// A machine's inline read: Check (`doctor`), Addresses (`resolve`) or
/// Credentials (`credentials list`), with Run again and a close.
struct MachinePanelView: View {
    @Environment(\.dmMetrics) private var m
    let panel: MachineDetailsStore.Panel
    let machine: ConfiguredMachine
    @ObservedObject var details: MachineDetailsStore

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            HStack(spacing: m.space.sm) {
                Text(verbatim: title)
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Spacer()
                DMButton("Run again", systemImage: "arrow.clockwise", variant: .ghost, size: .small) {
                    Task { await details.read(panel, machine: machine.name, isSelf: machine.isSelf) }
                }
                DMButton(icon: "xmark", label: "Close") {
                    Task { await details.toggle(panel, machine: machine.name, isSelf: machine.isSelf) }
                }
            }
            content
        }
        .padding(m.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(Color.dmBand, radius: DMRadius.control)
    }

    private var title: String {
        switch panel {
        case .check: return machine.isSelf ? "devmachine machine doctor" : "devmachine doctor --machine \(machine.name)"
        case .addresses: return "devmachine resolve --machine \(machine.name)"
        case .credentials: return "devmachine credentials list --machine \(machine.name)"
        case .passwordLogin: return "devmachine machines password-login \(machine.name)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .check: read(details.checks[machine.name]) { checks($0) }
        case .addresses: read(details.addresses[machine.name]) { addresses($0) }
        case .credentials: read(details.credentials[machine.name]) { credentials($0) }
        case .passwordLogin:
            read(details.passwordLogins[machine.name]) {
                MachinePasswordLoginPanel(report: $0, machine: machine, details: details)
            }
        }
    }

    @ViewBuilder
    private func read<Value: Equatable, Content: View>(
        _ state: MachineRead<Value>?, @ViewBuilder content: (Value) -> Content
    ) -> some View {
        switch state {
        case .none, .loading:
            ProgressView().controlSize(.small)
        case let .failed(message):
            DMErrorStateView(
                state: DMErrorState(title: "Could not read \(machine.name)", message: message),
                retry: { Task { await details.read(panel, machine: machine.name, isSelf: machine.isSelf) } })
        case let .loaded(value):
            content(value)
        }
    }

    @ViewBuilder
    private func checks(_ outcome: DevmachineCLI.DoctorOutcome) -> some View {
        switch outcome {
        case let .report(report):
            VStack(alignment: .leading, spacing: m.space.xs) {
                ForEach(report.checks) { check in
                    HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
                        Image(systemName: check.status.systemImage)
                            .foregroundStyle(check.status.color)
                        Text(verbatim: check.name)
                            .font(.dm(11.5, weight: .medium))
                            .foregroundStyle(Color.dmRowText)
                        Text(verbatim: check.detail)
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .raw(text):
            DMLogView(lines: text.components(separatedBy: "\n"), title: "Output")
        }
    }

    private func addresses(_ report: MachineAddresses) -> some View {
        VStack(alignment: .leading, spacing: m.space.xs) {
            if report.addresses.isEmpty {
                note("No address works from here.")
            }
            ForEach(report.addresses, id: \.address) { address in
                HStack(spacing: m.space.sm) {
                    Text(verbatim: address.address)
                        .font(.dm(11.5, design: .monospaced))
                        .foregroundStyle(Color.dmRowText)
                        .textSelection(.enabled)
                    if address.isTailnet { DMKindLabel(text: "TAILNET") }
                    note(address.package.isEmpty ? "from \(address.source)"
                        : "from \(address.source), \(address.package)")
                }
            }
            ForEach(report.dropped, id: \.source) { dropped in
                note("skipped \(dropped.source): \(dropped.reason)")
            }
        }
    }

    private func credentials(_ report: MachineCredentials) -> some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            if report.missing.isEmpty, report.unknown.isEmpty {
                note(report.credentials.isEmpty
                    ? "Nothing installed here declares a credential."
                    : "Every credential its packages declare is there.")
            }
            ForEach(report.missing + report.unknown, id: \.key) { credential in
                VStack(alignment: .leading, spacing: m.space.xs) {
                    HStack(spacing: m.space.sm) {
                        Text(verbatim: credential.key)
                            .font(.dm(11.5, weight: .medium))
                            .foregroundStyle(Color.dmRowText)
                        DMPill(text: credential.status.uppercased(),
                               color: credential.status == "missing" ? .orange : Color.dmMuted)
                        note("\(credential.package), \(credential.kind)")
                    }
                    if let fix = credential.fix { DMCommandBlock(fix) }
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(11))
            .foregroundStyle(Color.dmMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Who logs in over SSH with a password, as the machine's sshd says, and the
/// change: tick the accounts that keep it, or give it back to everybody.
struct MachinePasswordLoginPanel: View {
    @Environment(\.dmMetrics) private var m
    let report: MachinePasswordLogin
    let machine: ConfiguredMachine
    @ObservedObject var details: MachineDetailsStore
    @State private var kept: Set<String> = []

    private var hasHardening: Bool { machine.packages.contains("ssh_hardening") }
    private var changing: Bool { details.changingPasswordLogin == machine.name }
    private var chosen: [String] { report.accounts.map(\.user).filter(kept.contains) }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            Text(verbatim: report.summary)
                .font(.dm(11.5, weight: .medium))
                .foregroundStyle(Color.dmRowText)
            Text(verbatim: "Only SSH. The login window, sudo and Screen Sharing keep their passwords. "
                + "The CLI makes the change over \(machine.adminUser)'s key.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            if report.accounts.isEmpty {
                Text(verbatim: "No account people log in with was found.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
            ForEach(report.accounts, id: \.user) { account in
                HStack(spacing: m.space.sm) {
                    Toggle(isOn: Binding(
                        get: { kept.contains(account.user) },
                        set: { if $0 { kept.insert(account.user) } else { kept.remove(account.user) } })) {
                        Text(verbatim: account.user)
                            .font(.dm(11.5, design: .monospaced))
                            .foregroundStyle(Color.dmRowText)
                    }
                    .toggleStyle(.checkbox)
                    DMPill(text: account.allowed ? "PASSWORD OR KEY" : "KEY ONLY",
                           color: account.allowed ? .orange : Color.dmMuted)
                }
            }
            if let error = details.passwordLoginError[machine.name] {
                Text(verbatim: error)
                    .font(.dm(11))
                    .foregroundStyle(Color.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: m.space.sm) {
                DMButton(chosen.isEmpty ? "Off for every account" : "Off, except the ticked accounts",
                         variant: .primary, size: .small, isLoading: changing) {
                    Task { await details.changePasswordLogin(.keep(chosen), machine: machine.name) }
                }
                DMButton("On for every account", variant: .outline, size: .small) {
                    Task { await details.changePasswordLogin(.on, machine: machine.name) }
                }
                .disabled(hasHardening || changing)
                .help(hasHardening
                    ? "ssh_hardening turns it off again on every sync. Tick accounts instead, or remove the package."
                    : "Takes the CLI's file away, so the system's own setting applies again.")
            }
        }
        .onAppear { kept = Set(report.accounts.filter(\.allowed).map(\.user)) }
        .onChange(of: report) { _, new in kept = Set(new.accounts.filter(\.allowed).map(\.user)) }
    }
}
