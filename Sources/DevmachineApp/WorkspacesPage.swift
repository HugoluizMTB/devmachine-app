import SwiftUI
import DevmachineCore

/// Every workspace by machine, with what the last sync applied, and the
/// flows that add, change, forget and destroy one. A central page: the
/// sidebar's +, ⌘K and Settings → Workspaces open it. Every change is a
/// `devmachine` command shown before it runs.
struct WorkspacesPage: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: WorkspacesStore
    @ObservedObject private var runner: MachineStepRunner
    @ObservedObject private var machines: MachinesStore

    init(store: WorkspacesStore = .shared) {
        self.store = store
        _runner = ObservedObject(wrappedValue: store.runner)
        _machines = ObservedObject(wrappedValue: store.machines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            header
            if let flow = store.flow {
                WorkspaceFlowView(store: store, runner: runner, flow: flow)
            } else {
                ScrollView { list.frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .padding(m.space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.dmContentBg)
        .task {
            store.openPage()
            takeNewWorkspaceRequest()
            await store.load()
        }
        .onChange(of: model.pendingNewWorkspace) { _, _ in takeNewWorkspaceRequest() }
    }

    private func takeNewWorkspaceRequest() {
        guard model.pendingNewWorkspace else { return }
        model.pendingNewWorkspace = false
        Task { await store.startNew() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.md) {
            VStack(alignment: .leading, spacing: m.space.xs) {
                Text(verbatim: WorkspacesContent.title(store.flow))
                    .font(.dm(17, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Text(verbatim: WorkspacesContent.subtitle(store.flow))
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if store.flow == nil {
                DMButton(icon: "arrow.clockwise", label: "Refresh", size: .small) { Task { await store.load() } }
                DMButton("Sidebar visibility", variant: .ghost, size: .small) { model.openSettings(.workspaces) }
                DMButton("New workspace", systemImage: "plus", size: .small) { Task { await store.startNew() } }
                    .disabled(store.machineChoices.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        switch store.phase {
        case .loading where store.snapshot == nil:
            ProgressView().controlSize(.small)
        case let .failed(error) where store.snapshot == nil:
            DMErrorStateView(state: error, retry: { Task { await store.load() } })
        default:
            if store.machineChoices.isEmpty, machines.snapshot != nil {
                emptyState(
                    "A workspace lives on a machine, and there is none yet besides this Mac.",
                    button: "Add a machine") { model.showPage(.addMachine) }
            } else if store.groups.isEmpty {
                emptyState(WorkspacesContent.explanation, button: "New workspace") {
                    Task { await store.startNew() }
                }
            } else {
                VStack(alignment: .leading, spacing: m.space.xl) {
                    ForEach(store.groups) { group in
                        machineGroup(group)
                    }
                }
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

    private func machineGroup(_ group: WorkspacesStore.MachineGroup) -> some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            DMSectionLabel(text: group.machine.uppercased())
            VStack(spacing: 0) {
                ForEach(Array(group.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    DMTableRow(index: index) { row(workspace) }
                }
            }
        }
    }

    private func row(_ workspace: WorkspaceSummary) -> some View {
        HStack(alignment: .center, spacing: m.space.lg) {
            VStack(alignment: .leading, spacing: m.space.xxs) {
                Text(verbatim: workspace.name)
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Text(verbatim: "Linux account \(workspace.user)")
                    .font(.dm(10.5, design: .monospaced))
                    .foregroundStyle(Color.dmMuted)
            }
            .frame(width: m.pt(180), alignment: .leading)
            packages(workspace.packages)
                .frame(maxWidth: .infinity, alignment: .leading)
            syncPill(store.syncState(workspace))
            DMButton("Edit", systemImage: "slider.horizontal.3", variant: .ghost, size: .small) {
                store.startEdit(workspace.name)
            }
            DMButton("Forget…", variant: .ghost, size: .small) { store.startForget(workspace.name) }
            DMButton("Destroy…", variant: .ghostDanger, size: .small) { store.startDestroy(workspace.name) }
        }
        .padding(.vertical, m.space.xs)
    }

    @ViewBuilder
    private func packages(_ names: [String]) -> some View {
        if names.isEmpty {
            Text(verbatim: "Only the account, no packages")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
        } else {
            FlowLayout(spacing: m.space.xs, rowSpacing: m.space.xs) {
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
                .help("Not on the machine yet: \(missing.joined(separator: ", ")). Edit it and apply, "
                    + "or run devmachine sync.")
        case .neverSynced:
            DMPill(text: "Not created yet", color: .orange)
                .help("No sync has created this account on its machine yet.")
        case .unknown:
            EmptyView()
        }
    }
}

/// A flow on screen: its form, the review of the exact commands, or the run.
private struct WorkspaceFlowView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var store: WorkspacesStore
    @ObservedObject var runner: MachineStepRunner
    let flow: WorkspaceFlow
    @State private var confirming = false

    var body: some View {
        if flow.stage == .run {
            MachineRunLayout(steps: flow.plan, runner: runner) { WorkspaceRunOutcome(store: store, runner: runner, flow: flow) }
        } else {
            HStack(alignment: .top, spacing: m.space.xl) {
                VStack(alignment: .leading, spacing: m.space.xl) {
                    ScrollView {
                        stageBody.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    footer
                }
                .frame(maxWidth: m.pt(760), alignment: .leading)
                if flow.stage == .form {
                    side.frame(width: m.pt(AddMachineContent.sideWidth))
                }
            }
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

    @ViewBuilder
    private var stageBody: some View {
        if flow.stage == .review {
            WorkspaceReview(flow: flow)
        } else {
            switch flow.action {
            case .new: WorkspaceNewForm(flow: flowBinding, cards: store.packageCards)
            case .edit: WorkspaceEditForm(flow: flowBinding, cards: store.packageCards)
            case .forget: WorkspaceForgetForm(flow: flow) { store.startDestroy(flow.name) }
            case .destroy: WorkspaceDestroyForm(flow: flowBinding)
            }
        }
    }

    private var side: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: m.space.lg) {
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
                    .disabled(!flow.canAdvance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct WorkspaceNewForm: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    let cards: [MachinePackageCard]

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
            WorkspacePackageCards(flow: $flow, cards: cards, note: WorkspacesContent.preselectionNote)
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

private struct WorkspaceEditForm: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    let cards: [MachinePackageCard]

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            WorkspacePackageCards(
                flow: $flow, cards: cards,
                note: "Ticked: what \(flow.name) asks for now. A package taken off stays installed on the machine; "
                    + "the sync only stops managing it.")
            settings
            WorkspaceSyncToggle(sync: $flow.sync, machine: flow.machine)
            AddMachineNote(text: "The machine, the Linux account and shared logins are not changed here: "
                + "use devmachine workspaces edit --user or --share in a terminal.")
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            AddMachineFieldLabel(text: "Settings")
            Text(verbatim: "A package's variables, written as <package>.<name>, like zsh.theme. "
                + "The CLI reads each value as YAML.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(flow.settings.indices), id: \.self) { index in
                settingRow(index)
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

private struct WorkspacePackageCards: View {
    @Environment(\.dmMetrics) private var m
    @Binding var flow: WorkspaceFlow
    let cards: [MachinePackageCard]
    let note: String

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
            ForEach(WorkspacePackageCatalog.groups(cards), id: \.title) { group in
                VStack(alignment: .leading, spacing: m.space.sm) {
                    DMSectionLabel(text: group.title.uppercased())
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
        }
    }

    private func badge(_ card: MachinePackageCard) -> String? {
        if card.isLocked { return "ALWAYS INSTALLED" }
        if card.isRecommended { return "DEFAULT" }
        return card.isYours ? "YOURS" : nil
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
        + "If you changed defaults.workspace, tick what you want here: the app cannot read it."

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
        case .edit: return "On \(flow?.machine ?? ""). Its packages and settings, then a sync applies them."
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
            return "The log on the left lists what was removed, and any DNS record to remove by hand."
        }
    }
}
