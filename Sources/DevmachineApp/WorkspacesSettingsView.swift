import SwiftUI
import DevmachineCore

/// Settings → Workspaces: every workspace under its machine, each with its
/// on/off switch, and the flows that add, change, forget and destroy one.
/// A flow opens in place, under a breadcrumb back to the list, and is
/// dropped when the section is left (`WorkspacesStore.leave`). Every change
/// is a `devmachine` command shown before it runs.
struct WorkspacesSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: WorkspacesStore
    @ObservedObject private var runner: MachineStepRunner
    @ObservedObject private var machines: MachinesStore
    /// Settings' draft of the sidebar's hidden list, by ssh alias.
    let hiddenWorkspaces: [String]
    let setActive: (_ alias: String, _ active: Bool) -> Void

    init(
        store: WorkspacesStore = .shared, hiddenWorkspaces: [String],
        setActive: @escaping (_ alias: String, _ active: Bool) -> Void
    ) {
        self.store = store
        self.hiddenWorkspaces = hiddenWorkspaces
        self.setActive = setActive
        _runner = ObservedObject(wrappedValue: store.runner)
        _machines = ObservedObject(wrappedValue: store.machines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(18)) {
            header
            if let flow = store.flow {
                WorkspaceFlowView(store: store, runner: runner, flow: flow)
            } else {
                ScrollView { list.frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            store.openPage()
            takeNewWorkspaceRequest()
            await store.load()
        }
        .onChange(of: model.pendingNewWorkspace) { _, _ in takeNewWorkspaceRequest() }
        .onDisappear { store.leave() }
    }

    private func takeNewWorkspaceRequest() {
        guard model.pendingNewWorkspace else { return }
        model.pendingNewWorkspace = false
        Task { await store.startNew() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.md) {
            VStack(alignment: .leading, spacing: m.space.xs) {
                breadcrumb
                Text(verbatim: WorkspacesContent.subtitle(store.flow))
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if store.flow == nil {
                DMButton(icon: "arrow.clockwise", label: "Refresh", size: .small) { Task { await store.load() } }
                DMButton("New workspace", systemImage: "plus", size: .small) { Task { await store.startNew() } }
                    .disabled(store.machineChoices.isEmpty)
            }
        }
    }

    /// "Workspaces" alone on the list; "Workspaces › Edit acme" in a flow,
    /// where "Workspaces" goes back (not while a run is going: Stop first).
    @ViewBuilder
    private var breadcrumb: some View {
        let crumbs = WorkspacesContent.breadcrumb(store.flow)
        HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
            if crumbs.count > 1 {
                DMButton(crumbs[0], variant: .link, size: .large) { store.close() }
                    .disabled(!WorkspacesContent.canLeaveFlow(isRunning: store.isRunning))
                    .help(store.isRunning ? "Stop the run first." : "Back to every workspace")
                Image(systemName: "chevron.right")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(verbatim: crumbs[crumbs.count - 1])
                .font(.dm(15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var sections: [WorkspaceSettingsList.Section] {
        store.sections(sidebar: model.workspaces, hidden: hiddenWorkspaces)
    }

    @ViewBuilder
    private var list: some View {
        switch store.phase {
        case .loading where store.snapshot == nil:
            ProgressView().controlSize(.small)
        case let .failed(error) where store.snapshot == nil:
            VStack(alignment: .leading, spacing: m.space.xl) {
                DMErrorStateView(state: error, retry: { Task { await store.load() } })
                sectionList
            }
        default:
            if store.machineChoices.isEmpty, machines.snapshot != nil, sections.isEmpty {
                emptyState(
                    "A workspace lives on a machine, and there is none yet besides this Mac.",
                    button: "Add a machine") { model.showPage(.addMachine) }
            } else if sections.isEmpty {
                emptyState(WorkspacesContent.explanation, button: "New workspace") {
                    Task { await store.startNew() }
                }
            } else {
                sectionList
            }
        }
    }

    private var sectionList: some View {
        VStack(alignment: .leading, spacing: m.space.xxl) {
            ForEach(sections) { section in
                machineSection(section)
            }
            if !sections.isEmpty {
                AddMachineNote(text: "A workspace turned off leaves the sidebar, and the app stops reaching it: "
                    + "no ssh, no mosh, no poll. Its sessions keep running on the machine and come back the moment "
                    + "you turn it on again. This Mac cannot be turned off.")
            }
        }
    }

    private func emptyState(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: text)
                .font(.dm(12))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            DMButton(button, systemImage: "plus", size: .small, action: action)
        }
        .padding(m.space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }

    private func machineSection(_ section: WorkspaceSettingsList.Section) -> some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            machineTitle(section)
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    DMTableRow(index: index) { self.row(row) }
                }
            }
        }
    }

    private func machineTitle(_ section: WorkspaceSettingsList.Section) -> some View {
        let known = section.machine != WorkspaceSettingsList.unknownMachine
        return HStack(alignment: .firstTextBaseline, spacing: m.space.md) {
            Label {
                Text(verbatim: known ? section.machine : "Other workspaces")
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(.white)
            } icon: {
                Image(systemName: known ? "server.rack" : "questionmark.square.dashed")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let location = section.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if !known {
                Text(verbatim: "The sidebar knows these; the CLI's list does not say where they live.")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(verbatim: section.rows.count == 1 ? "1 workspace" : "\(section.rows.count) workspaces")
                .font(.dm(11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, m.space.sm)
    }

    private func row(_ row: WorkspaceSettingsList.Row) -> some View {
        HStack(alignment: .center, spacing: m.space.lg) {
            activeSwitch(row)
            VStack(alignment: .leading, spacing: m.space.xxs) {
                Text(verbatim: row.name)
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmRowText.opacity(row.isActive ? 1 : 0.55))
                Text(verbatim: row.summary.map { "Linux account \($0.user)" } ?? (row.alias ?? ""))
                    .font(.dm(10.5, design: .monospaced))
                    .foregroundStyle(Color.dmMuted)
            }
            .frame(width: m.pt(180), alignment: .leading)
            if let summary = row.summary {
                packages(summary.packages)
                    .frame(maxWidth: .infinity, alignment: .leading)
                syncPill(store.syncState(summary))
                DMButton("Edit", systemImage: "slider.horizontal.3", variant: .ghost, size: .small) {
                    store.startEdit(summary.name)
                }
                DMButton("Forget…", variant: .ghost, size: .small) { store.startForget(summary.name) }
                DMButton("Destroy…", variant: .ghostDanger, size: .small) { store.startDestroy(summary.name) }
            } else {
                Spacer()
            }
        }
        .padding(.vertical, m.space.xs)
    }

    @ViewBuilder
    private func activeSwitch(_ row: WorkspaceSettingsList.Row) -> some View {
        let toggle = Toggle(isOn: Binding(
            get: { row.isActive },
            set: { on in if let alias = row.alias { setActive(alias, on) } }
        )) {
            Text(verbatim: row.isActive ? "On" : "Off")
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        if row.alias == nil {
            toggle.disabled(true)
                .help("The sidebar does not list \(row.name) yet, so there is nothing to turn off.")
        } else {
            toggle.help(row.isActive
                ? "On: in the sidebar, and the app reaches it. Turn off to stop every ssh, mosh and poll."
                : "Off: not in the sidebar, and the app never reaches it.")
        }
    }

    @ViewBuilder
    private func packages(_ names: [String]) -> some View {
        if names.isEmpty {
            Text(verbatim: "Only the account, no packages")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
        } else {
            FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                ForEach(names, id: \.self) { DMKindLabel(text: $0) }
            }
        }
    }

    @ViewBuilder
    private func syncPill(_ state: WorkspaceSyncState) -> some View {
        switch state {
        case .applied:
            DMPill(text: "Applied", color: .green)
                .help("The last sync installed every package it asks for.")
        case let .pending(missing):
            DMPill(text: "Waiting for sync", color: .orange)
                .help("Not on the machine yet: \(missing.joined(separator: ", ")). Sync its machine, "
                    + "or run devmachine sync.")
        case .neverSynced:
            DMPill(text: "Not created yet", color: .orange)
                .help("No sync has created this account on its machine yet.")
        case .unknown:
            EmptyView()
        }
    }
}

/// A flow on screen, the whole width and down to the bottom: its form, the
/// review of the exact commands, or the run. Forget and Destroy have no
/// review, so their form shows the one command it runs.
private struct WorkspaceFlowView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: WorkspacesStore
    @ObservedObject var runner: MachineStepRunner
    let flow: WorkspaceFlow
    @State private var confirming = false

    var body: some View {
        if flow.stage == .run {
            MachineRunLayout(steps: flow.plan, runner: runner) { WorkspaceRunOutcome(store: store, runner: runner, flow: flow) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: m.space.xl) {
                ScrollView {
                    stageBody.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .confirmationDialog(WorkspacesContent.confirmTitle(flow), isPresented: $confirming) {
                Button(WorkspacesContent.runTitle(flow), role: flow.action == .new ? nil : .destructive) {
                    Task { await store.run() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(verbatim: WorkspacesContent.confirmMessage(flow))
            }
        }
    }

    private var flowBinding: Binding<WorkspaceFlow> {
        Binding(get: { store.flow ?? flow }, set: { store.flow = $0 })
    }

    private var agents: WorkspaceAgentsNote {
        WorkspaceAgentsNote(noneOn: store.noCodingAgentOn) { model.openSettings(.harnesses) }
    }

    @ViewBuilder
    private var stageBody: some View {
        if flow.stage == .review {
            WorkspaceReview(flow: flow)
        } else {
            switch flow.action {
            case .new:
                WorkspaceNewForm(
                    flow: flowBinding, cards: store.packageCards, agents: agents,
                    note: WorkspacesContent.preselectionNote(defaults: store.knowsDefaults ? store.defaults : nil))
            case .edit:
                WorkspaceEditForm(
                    flow: flowBinding, variables: store.variables,
                    logins: store.reportsSharing ? store.logins : nil
                ) { model.openPackages(workspace: flow.name) }
            case .forget:
                WorkspaceForgetForm(flow: flow) { store.startDestroy(flow.name) }
            case .destroy:
                WorkspaceDestroyForm(flow: flowBinding)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: m.space.sm) {
            if flow.canGoBack {
                DMButton("Back", variant: .outline) { store.back() }
            }
            DMButton("Cancel", variant: .ghost) { store.close() }
            Spacer()
            switch (flow.stage, flow.action) {
            case (.review, _), (.form, .forget):
                DMButton(
                    WorkspacesContent.runTitle(flow), systemImage: "play.fill",
                    variant: flow.isForget ? .dangerOutline : .primary
                ) { confirming = true }
                .keyboardShortcut(.defaultAction)
            case (.form, .destroy):
                DMButton(WorkspacesContent.runTitle(flow), systemImage: "trash", variant: .danger) {
                    Task { await store.run() }
                }
                .disabled(!flow.canAdvance)
            default:
                DMButton("Continue") { store.next() }
                    .disabled(!store.canContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The one command Forget or Destroy runs, on its own screen.
private struct WorkspaceCommandPreview: View {
    @Environment(\.dmMetrics) private var m
    let flow: WorkspaceFlow

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            AddMachineFieldLabel(text: "What will run")
            if flow.canAdvance || flow.isForget {
                DMCommandBlock(flow.plan.map(\.displayLine), wraps: true)
            } else {
                Text(verbatim: WorkspacesContent.waitingForAnswers(flow))
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AddMachineNote(text: WorkspacesContent.sideNote(flow))
        }
    }
}

private struct WorkspaceNewForm: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    let cards: [MachinePackageCard]
    let agents: WorkspaceAgentsNote
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            WorkspaceField(
                title: "Name",
                hint: WorkspacesContent.nameHint,
                problem: flow.draft.name.isEmpty ? nil : flow.nameProblem
            ) {
                TextField(WorkspaceName.example, text: $flow.draft.name).dmField()
            }
            machinePicker
            WorkspacePackageCards(flow: $flow, cards: cards, note: note, agents: agents)
            WorkspaceSyncToggle(sync: $flow.sync, machine: flow.machine)
        }
    }

    @ViewBuilder
    private var machinePicker: some View {
        WorkspaceField(
            title: "Machine",
            hint: "Where its sessions run. This Mac is never offered: local sessions need no workspace.",
            problem: flow.machines.isEmpty ? "Add a machine first." : nil
        ) {
            if flow.machines.count > 1, flow.machines.count <= 5 {
                DMTabStrip(
                    tabs: flow.machines.map(\.name), selection: $flow.draft.machine, title: { $0 },
                    fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
                    .fixedSize()
            } else if flow.machines.count > 5 {
                Picker("Machine", selection: $flow.draft.machine) {
                    ForEach(flow.machines) { Text(verbatim: $0.name).tag($0.name) }
                }
                .labelsHidden()
                .frame(width: m.pt(240))
            } else if let only = flow.machines.first {
                Text(verbatim: only.name)
                    .font(.dm(12.5, weight: .medium))
                    .foregroundStyle(Color.dmRowText)
            }
        }
    }
}

/// Edit changes the workspace's own settings and logins. Its packages are
/// Settings → Packages' job: the link opens it on this workspace.
private struct WorkspaceEditForm: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    /// What each package declares (CLI 0.7.29+); empty, settings are free text.
    let variables: [(package: String, variables: [PackageVariable])]
    /// Nil on a CLI that does not report login answers.
    let logins: [WorkspaceLogin]?
    let openPackages: () -> Void

    private var declaredKeys: Set<String> {
        Set(variables.flatMap { package, declared in declared.map { "\(package).\($0.name)" } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            packages
            if !variables.isEmpty {
                ForEach(variables, id: \.package) { package, declared in
                    WorkspaceVariableFields(flow: $flow, package: package, variables: declared)
                }
            }
            settings
            if let logins, !logins.isEmpty {
                WorkspaceLoginSharing(flow: $flow, logins: logins)
            }
            WorkspaceSyncToggle(sync: $flow.sync, machine: flow.machine)
            AddMachineNote(text: logins == nil
                ? "The machine, the Linux account and shared logins are not changed here: "
                    + "use devmachine workspaces edit --user or --share in a terminal."
                : "The machine and the Linux account are not changed here: use devmachine workspaces edit "
                    + "--machine or --user in a terminal.")
        }
    }

    private var packages: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            AddMachineFieldLabel(text: "Packages")
            HStack(alignment: .center, spacing: m.space.md) {
                if flow.packages.isEmpty {
                    Text(verbatim: "Only the account, no packages")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                } else {
                    FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                        ForEach(flow.packages, id: \.self) { DMKindLabel(text: $0) }
                    }
                }
                Spacer(minLength: m.space.md)
                DMButton(WorkspacesContent.packagesLink, variant: .link, size: .small, action: openPackages)
            }
            Text(verbatim: "Packages are added and removed in Settings → Packages. Here: their settings and logins.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            AddMachineFieldLabel(text: variables.isEmpty ? "Settings" : "Other settings")
            Text(verbatim: variables.isEmpty
                ? "A package's variables, written as <package>.<name>, like zsh.theme. The CLI reads each value as YAML."
                : "Settings no package above declares, written as <package>.<name>. The CLI reads each value as YAML.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(flow.settings.indices), id: \.self) { index in
                if !declaredKeys.contains(flow.settings[index].key) {
                    settingRow(index)
                }
            }
            DMButton("Add a setting", systemImage: "plus", variant: .ghost, size: .small) { flow.addSetting() }
        }
    }

    private func settingRow(_ index: Int) -> some View {
        let setting = flow.settings[index]
        let touched = !setting.key.isEmpty || !setting.value.isEmpty
        let problem = touched ? setting.problem(packages: flow.packages) : nil
        return VStack(alignment: .leading, spacing: m.space.xxs) {
            HStack(spacing: m.space.sm) {
                TextField("zsh.theme", text: $flow.settings[index].key)
                    .font(.system(size: m.pt(11.5), design: .monospaced))
                    .dmField()
                    .frame(width: m.pt(220))
                TextField("value", text: $flow.settings[index].value)
                    .font(.system(size: m.pt(11.5), design: .monospaced))
                    .dmField()
                DMButton(icon: "minus.circle", label: "Remove \(setting.key)", size: .small) {
                    flow.removeSetting(at: index)
                }
            }
            if let problem {
                WorkspaceWarning(text: problem)
            }
        }
    }
}

/// One package's declared settings as typed fields. An empty field (or
/// Default) leaves the package's default; the CLI validates every value.
private struct WorkspaceVariableFields: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    let package: String
    let variables: [PackageVariable]

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            AddMachineFieldLabel(text: "\(package) settings")
            ForEach(variables, id: \.name) { variable in
                field(variable)
            }
        }
    }

    private func key(_ variable: PackageVariable) -> String { "\(package).\(variable.name)" }

    private func binding(_ variable: PackageVariable) -> Binding<String> {
        Binding(get: { flow.settingValue(key(variable)) }, set: { flow.setSetting(key(variable), $0) })
    }

    @ViewBuilder
    private func field(_ variable: PackageVariable) -> some View {
        let value = flow.settingValue(key(variable))
        VStack(alignment: .leading, spacing: m.space.xxs) {
            HStack(spacing: m.space.md) {
                Text(verbatim: variable.name)
                    .font(.dm(11.5, design: .monospaced))
                    .foregroundStyle(Color.dmRowText)
                    .frame(width: m.pt(160), alignment: .leading)
                if variable.type == .boolean {
                    DMTabStrip(
                        tabs: ["", "true", "false"], selection: binding(variable),
                        title: { $0.isEmpty ? "Default (\(variable.defaultText))" : ($0 == "true" ? "On" : "Off") },
                        fontSize: 11.5, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
                        .fixedSize()
                } else {
                    TextField(variable.defaultText, text: binding(variable))
                        .font(.system(size: m.pt(11.5), design: .monospaced))
                        .dmField()
                }
            }
            if let problem = variable.problem(value) {
                WorkspaceWarning(text: problem)
            } else {
                Text(verbatim: hint(variable))
                    .font(.dm(10.5))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hint(_ variable: PackageVariable) -> String {
        var parts = [variable.summary.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        switch variable.type {
        case .list: parts.append("A list, like [a, b].")
        case .map: parts.append("A map, like {key: value}.")
        default: break
        }
        parts.append("Empty keeps the default: \(variable.defaultText).")
        return parts.joined(separator: " ")
    }
}

/// Each login the workspace's packages use: follow the configuration, or
/// say here that it is shared from the machine or kept by the workspace.
private struct WorkspaceLoginSharing: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    let logins: [WorkspaceLogin]

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            AddMachineFieldLabel(text: "Logins")
            Text(verbatim: "Shared: one login on the machine, copied into this workspace. Own: this workspace "
                + "logs in for itself, for example to another account.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(logins) { login in
                HStack(spacing: m.space.md) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: login.name)
                            .font(.dm(12, weight: .medium))
                            .foregroundStyle(Color.dmRowText)
                        Text(verbatim: "from \(login.package)")
                            .font(.dm(10.5))
                            .foregroundStyle(Color.dmMuted)
                    }
                    .frame(width: m.pt(160), alignment: .leading)
                    DMTabStrip(
                        tabs: login.choices,
                        selection: Binding(
                            get: { flow.sharing[login.name] ?? "" },
                            set: { flow.setSharing(login.name, $0.isEmpty ? nil : $0) }),
                        title: { title($0, login: login) },
                        fontSize: 11.5, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
                        .fixedSize()
                }
                if let reason = login.unshareableReason {
                    Text(verbatim: reason)
                        .font(.dm(10.5))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func title(_ value: String, login: WorkspaceLogin) -> String {
        switch value {
        case WorkspaceLogin.machine: return "Shared"
        case WorkspaceLogin.own: return "Own"
        default: return "As configured (\(login.inherited == WorkspaceLogin.machine ? "shared" : "own"))"
        }
    }
}

private struct WorkspacePackageCards: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    let cards: [MachinePackageCard]
    let note: String
    let agents: WorkspaceAgentsNote

    private var groups: [WorkspacePackageCatalog.Group] { WorkspacePackageCatalog.groups(cards) }
    private static let agentsTitle = "Coding agents"

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            VStack(alignment: .leading, spacing: m.space.xs) {
                AddMachineFieldLabel(text: "Packages")
                Text(verbatim: note)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if cards.isEmpty {
                AddMachineNote(text: "The package list could not be read. The workspace gets only its account; "
                    + "add packages later with devmachine workspaces edit.")
            }
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: m.space.sm) {
                    DMSectionLabel(text: group.title.uppercased())
                    if group.title == Self.agentsTitle { agents }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: m.pt(240)), spacing: m.space.md, alignment: .top)],
                        alignment: .leading, spacing: m.space.md
                    ) {
                        ForEach(group.cards) { card in
                            DMChoiceCard(
                                title: card.name, detail: card.summary, badge: badge(card),
                                selected: flow.isSelected(card.name), multiple: true, locked: card.isLocked
                            ) { flow.togglePackage(card.name) }
                        }
                    }
                }
            }
            if !groups.contains(where: { $0.title == Self.agentsTitle }) {
                VStack(alignment: .leading, spacing: m.space.sm) {
                    DMSectionLabel(text: Self.agentsTitle.uppercased())
                    agents
                }
            }
        }
    }

    private func badge(_ card: MachinePackageCard) -> String? {
        if card.isLocked { return "ALWAYS INSTALLED" }
        if card.isRecommended { return "DEFAULT" }
        return card.isYours ? "YOURS" : nil
    }
}

/// Coding agents are offered only for the harnesses turned on; the link
/// goes to where they are turned on.
private struct WorkspaceAgentsNote: View {
    @Environment(\.dmMetrics) private var m
    let noneOn: Bool
    let openHarnesses: () -> Void

    var body: some View {
        HStack(spacing: m.space.sm) {
            Text(verbatim: noneOn
                ? "No coding agent is turned on, so none is offered here."
                : "Only the coding agents turned on in Settings are offered.")
                .font(.dm(11))
                .foregroundStyle(noneOn ? Color.orange : Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            DMButton("Settings → Harnesses", variant: .link, size: .small, action: openHarnesses)
        }
    }
}

private struct WorkspaceSyncToggle: View {
    @Environment(\.dmMetrics) private var m
    @Binding var sync: Bool
    let machine: String

    var body: some View {
        Toggle(isOn: $sync) {
            VStack(alignment: .leading, spacing: m.space.xxs) {
                Text(verbatim: "Apply it now")
                    .font(.dm(12, weight: .medium))
                    .foregroundStyle(Color.dmRowText)
                Text(verbatim: "Runs devmachine sync on \(machine.isEmpty ? "the machine" : machine) at the end, "
                    + "which also applies anything else waiting there. Off, the change stays in the "
                    + "configuration until the next sync.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

private struct WorkspaceReview: View {
    @Environment(\.dmMetrics) private var m
    let flow: WorkspaceFlow

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: "These run in order on the next step, here, with every log shown.")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            DMCommandBlock(flow.plan.map(\.displayLine), wraps: true)
            AddMachineNote(text: WorkspacesContent.reviewNote(flow))
        }
    }
}

private struct WorkspaceForgetForm: View {
    @Environment(\.dmMetrics) private var m
    let flow: WorkspaceFlow
    let destroyInstead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: "Forget only takes \(flow.name) out of devmachine's configuration on this Mac.")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            VStack(alignment: .leading, spacing: m.space.sm) {
                bullet("The Linux account \(flow.current?.user ?? flow.name), its home and its files stay on "
                    + "\(flow.machine).")
                bullet("Its sessions keep running there. The app stops listing them once the sidebar reloads.")
                bullet("A sync no longer manages it, and nothing on the machine is changed now.")
            }
            AddMachineNote(text: "If \(flow.name) publishes a site through another machine, the CLI refuses: "
                + "that machine would keep serving it. Its message shows here; remove the site first.")
            HStack(spacing: m.space.sm) {
                Text(verbatim: "Want the account and its home gone too?")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMButton("Destroy instead…", variant: .link, size: .small, action: destroyInstead)
            }
            WorkspaceCommandPreview(flow: flow)
        }
    }

    private func bullet(_ text: String) -> some View {
        Label { Text(verbatim: text).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: "checkmark.circle")
        }
        .font(.dm(12))
        .foregroundStyle(Color.dmRowText.opacity(0.85))
    }
}

private struct WorkspaceDestroyForm: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow

    private var user: String { flow.current?.user ?? flow.name }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            VStack(alignment: .leading, spacing: m.space.sm) {
                Label {
                    Text(verbatim: "This deletes, on \(flow.machine), for good")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.red)
                bullet("The account \(user) and everything under /home/\(user).")
                bullet("Its published sites: Caddy stops answering for them.")
                bullet(flow.keepDNS
                    ? "Not the DNS records of those sites: --keep-dns leaves them, and the CLI prints how to "
                        + "remove each later."
                    : "The DNS record of each site, while it still points at the machine that serves it.")
                bullet("\(flow.name) in devmachine's configuration.")
            }
            .padding(m.space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dmSurface(Color.red.opacity(0.08), radius: DMRadius.panel)
            Toggle(isOn: $flow.keepDNS) {
                Text(verbatim: "Keep the DNS records of its sites (--keep-dns)")
                    .font(.dm(12))
                    .foregroundStyle(Color.dmRowText)
            }
            .toggleStyle(.checkbox)
            WorkspaceField(
                title: "Type \(flow.name) to confirm",
                hint: "There is no undo. Forget keeps the account instead.",
                problem: !flow.typedName.isEmpty && !flow.canAdvance ? "That is not \(flow.name)." : nil
            ) {
                TextField(flow.name, text: $flow.typedName).dmField()
            }
            AddMachineNote(text: "It needs \(flow.machine) to answer, and any machine that publishes its sites. "
                + "If the CLI refuses, its reason shows here and nothing is deleted.")
            WorkspaceCommandPreview(flow: flow)
        }
    }

    private func bullet(_ text: String) -> some View {
        Label { Text(verbatim: text).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: "minus.circle")
        }
        .font(.dm(12))
        .foregroundStyle(Color.dmRowText.opacity(0.85))
    }
}

private struct WorkspaceRunOutcome: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var store: WorkspacesStore
    @ObservedObject var runner: MachineStepRunner
    let flow: WorkspaceFlow

    var body: some View {
        switch runner.phase {
        case .succeeded:
            VStack(alignment: .leading, spacing: m.space.md) {
                Label {
                    Text(verbatim: WorkspacesContent.doneTitle(flow))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                }
                .font(.dm(14, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                Text(verbatim: WorkspacesContent.doneDetail(flow))
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                DMButton("Done") { store.close() }
            }
        case .failed:
            SetupFailurePanel(
                step: store.failedStep, lines: runner.lines, problem: runner.problem, exitCode: runner.exitCode,
                onRetry: { Task { await store.retry() } },
                onEditAnswers: store.canEditAnswers ? { store.editAnswers() } : nil)
            DMButton("Close", variant: .ghost, size: .small) { store.close() }
        case .running, .idle:
            Text(verbatim: "Each step's log shows on the left as it runs. Nothing here asks a question.")
                .font(.dm(11.5))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            if runner.phase == .running {
                DMButton("Stop", systemImage: "stop.fill", variant: .dangerOutline, size: .small) { store.stop() }
            }
        }
    }
}

private struct WorkspaceField<Content: View>: View {
    @Environment(\.dmMetrics) private var m
    let title: String
    let hint: String
    let problem: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xs) {
            AddMachineFieldLabel(text: title)
            content()
            if let problem {
                WorkspaceWarning(text: problem)
            } else {
                Text(verbatim: hint)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WorkspaceWarning: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.dm(11))
            .foregroundStyle(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension WorkspaceFlow {
    var isForget: Bool {
        if case .forget = action { return true }
        return false
    }
}

enum WorkspacesContent {
    static let explanation = "A workspace is a Linux account on a machine, where your sessions run. "
        + "Make one per project or client, like acme, each with its own home, logins and tools."

    static let nameHint = "A Linux account on the machine where your sessions run. Name it after your "
        + "project, like acme: lower-case letters, digits, - and _."

    static let preselectionNote = "Ticked: what devmachine setup makes every new workspace get (dev, zsh, mise). "
        + "This devmachine CLI does not say what defaults.workspace holds; version 0.7.29 or newer does."

    static func preselectionNote(defaults: [String]?) -> String {
        guard let defaults else { return preselectionNote }
        return defaults.isEmpty
            ? "Nothing is ticked: defaults.workspace in your configuration is empty."
            : "Ticked: defaults.workspace in your configuration (\(defaults.joined(separator: ", ")))."
    }

    static let packagesLink = "Packages for this workspace →"

    /// The header's trail: the list's name, then the flow's.
    static func breadcrumb(_ flow: WorkspaceFlow?) -> [String] {
        flow == nil ? [title(nil)] : [title(nil), title(flow)]
    }

    /// A running flow is not left: its log would go with it. Stop ends it.
    static func canLeaveFlow(isRunning: Bool) -> Bool { !isRunning }

    static func title(_ flow: WorkspaceFlow?) -> String {
        switch flow?.action {
        case nil: return "Workspaces"
        case .new: return "New workspace"
        case let .edit(name): return "Edit \(name)"
        case let .forget(name): return "Forget \(name)"
        case let .destroy(name): return "Destroy \(name)"
        }
    }

    static func subtitle(_ flow: WorkspaceFlow?) -> String {
        switch flow?.action {
        case nil: return explanation
        case .new: return "A Linux account on a machine, with the packages you choose."
        case .edit: return "On \(flow?.machine ?? ""). Its settings and logins, then a sync applies them."
        case .forget: return "The account stays on \(flow?.machine ?? ""); only this configuration forgets it."
        case .destroy: return "Deletes the account, its home and its sites on \(flow?.machine ?? "")."
        }
    }

    static func runTitle(_ flow: WorkspaceFlow) -> String {
        switch flow.action {
        case .new: return "Create workspace"
        case .edit: return "Apply changes"
        case let .forget(name): return "Forget \(name)"
        case let .destroy(name): return "Destroy \(name)"
        }
    }

    static func confirmTitle(_ flow: WorkspaceFlow) -> String {
        switch flow.action {
        case .new: return "Create \(flow.name) on \(flow.machine)?"
        case let .edit(name): return "Change \(name)?"
        case let .forget(name): return "Forget \(name)?"
        case let .destroy(name): return "Destroy \(name)?"
        }
    }

    static func confirmMessage(_ flow: WorkspaceFlow) -> String {
        let sync = flow.sync
            ? " Then devmachine sync applies it on \(flow.machine), with anything else waiting there."
            : " Nothing reaches \(flow.machine) until the next sync."
        switch flow.action {
        case .new: return "devmachine adds \(flow.name) to the configuration on this Mac." + sync
        case .edit: return "devmachine changes \(flow.name) in the configuration on this Mac." + sync
        case .forget: return "Runs devmachine workspaces rm \(flow.name). The account and its home stay on "
            + "\(flow.machine); nothing there changes."
        case .destroy: return "Deletes the account, its home and its sites. There is no undo."
        }
    }

    static func waitingForAnswers(_ flow: WorkspaceFlow) -> String {
        switch flow.action {
        case .new: return "The commands show here once the workspace has a valid name and a machine."
        case .edit: return "The commands show here once something changed."
        case .forget, .destroy: return "The command shows here once the name is typed again."
        }
    }

    static func sideNote(_ flow: WorkspaceFlow) -> String {
        switch flow.action {
        case .new, .edit:
            return "workspaces commands only edit the configuration on this Mac; sync is what reaches the machine."
        case .forget:
            return "Forget changes only the configuration on this Mac. Destroy is the one that deletes on the machine."
        case .destroy:
            return "Destroy logs in to the machine as its admin and deletes the account. Forget never does."
        }
    }

    static func reviewNote(_ flow: WorkspaceFlow) -> String {
        let retry = " If a step fails, Retry starts again from that step."
        guard flow.sync else { return "Nothing reaches \(flow.machine) until you run devmachine sync." + retry }
        return "The sync applies every change waiting for \(flow.machine), not only this one. "
            + "A first sync of a workspace takes a few minutes." + retry
    }

    static func doneTitle(_ flow: WorkspaceFlow) -> String {
        switch flow.action {
        case .new: return flow.sync ? "\(flow.name) is ready" : "\(flow.name) is in the configuration"
        case let .edit(name): return flow.sync ? "\(name) is up to date" : "\(name) changed in the configuration"
        case let .forget(name): return "\(name) is forgotten"
        case let .destroy(name): return "\(name) is destroyed"
        }
    }

    static func doneDetail(_ flow: WorkspaceFlow) -> String {
        switch flow.action {
        case .new:
            return flow.sync
                ? "It shows in the sidebar. Start a session in it from the + beside its name."
                : "devmachine sync --machine \(flow.machine) creates the account."
        case .edit:
            return flow.sync ? "The machine has what it asks for." : "The next sync applies it."
        case .forget:
            return "The account \(flow.current?.user ?? flow.name) and its home are still on \(flow.machine)."
        case .destroy:
            return "The log lists what was removed, and any DNS record to remove by hand."
        }
    }
}
