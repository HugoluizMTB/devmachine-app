import SwiftUI
import DevmachineCore

/// The Add machine wizard, a central page: what kind of machine, its details,
/// its packages, the exact commands, then those commands running. Everything
/// it does is a `devmachine` command shown first. The first-run setup shows
/// the same wizard (`AddMachineWizardView`).
struct AddMachinePage: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var state: AddMachineModel
    @ObservedObject private var machines = MachinesStore.shared

    init(state: AddMachineModel = .shared) {
        self.state = state
    }

    var body: some View {
        AddMachineWizardView(state: state, title: "Add a machine", cards: machines.packageCards, onClose: close)
            .padding(m.space.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.dmContentBg)
            .onAppear {
                state.openPage()
                Task { await machines.load() }
            }
            .onDisappear { state.leavePage() }
    }

    private func close() {
        state.close()
        model.closeAddMachine()
    }
}

/// The wizard itself: stage pills, the stage on screen, Back / Continue,
/// and the run. `onClose` is Cancel, Close and Done.
struct AddMachineWizardView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel
    @ObservedObject private var runner: MachineStepRunner
    let title: String
    let cards: [MachinePackageCard]
    let onClose: () -> Void
    @State private var confirming = false

    init(state: AddMachineModel, title: String, cards: [MachinePackageCard], onClose: @escaping () -> Void) {
        self.state = state
        self.title = title
        self.cards = cards
        self.onClose = onClose
        _runner = ObservedObject(wrappedValue: state.runner)
    }

    private var wizard: MachineWizard { state.wizard }
    private var draft: MachineDraft { state.wizard.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            header
            if wizard.stage == .run {
                AddMachineRunView(state: state, runner: runner, onClose: onClose)
            } else {
                HStack(alignment: .top, spacing: m.space.xl) {
                    VStack(alignment: .leading, spacing: m.space.xl) {
                        ScrollView {
                            stageBody
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        footer
                    }
                    .frame(maxWidth: formWidth, alignment: .leading)
                    if wizard.stage != .kind {
                        AddMachineSummaryView(wizard: wizard)
                            .frame(width: m.pt(AddMachineContent.sideWidth))
                    }
                }
            }
        }
        .confirmationDialog(
            (wizard.firstRun ? "Set up " : "Create ") + draft.trimmedName + "?", isPresented: $confirming
        ) {
            Button(wizard.firstRun ? "Run the setup" : "Create machine") { Task { await state.create() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: AddMachineContent.confirmMessage(draft))
        }
    }

    /// The two kind cards take the summary's room too: nothing is chosen yet
    /// to summarise.
    private var formWidth: CGFloat {
        let form = m.pt(760)
        return wizard.stage == .kind ? form + m.space.xl + m.pt(AddMachineContent.sideWidth) : form
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: title)
                .font(.dm(17, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            HStack(spacing: m.space.sm) {
                ForEach(MachineWizardStage.allCases, id: \.self) { stage in
                    stagePill(stage)
                }
            }
        }
    }

    private func stagePill(_ stage: MachineWizardStage) -> some View {
        let current = stage == wizard.stage
        let reached = stage.rawValue <= wizard.stage.rawValue
        return Text(verbatim: "\(stage.rawValue + 1). \(stage.title)")
            .font(.dm(11, weight: current ? .semibold : .regular))
            .foregroundStyle(current ? Color.dmRowText : (reached ? Color.dmMuted : Color.dmMuted.opacity(0.6)))
            .padding(.horizontal, m.space.md)
            .padding(.vertical, m.space.xs)
            .background(current ? Color.dmSelection : Color.clear, in: Capsule())
    }

    @ViewBuilder
    private var stageBody: some View {
        switch wizard.stage {
        case .kind: AddMachineKindView(state: state)
        case .details: AddMachineDetailsView(state: state)
        case .packages: AddMachinePackagesView(state: state, cards: cards)
        case .review: AddMachineReviewView(wizard: wizard)
        case .run: EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: m.space.sm) {
            if wizard.canGoBack {
                DMButton("Back", variant: .outline) { state.wizard.back() }
            }
            DMButton(wizard.firstRun && !wizard.canGoBack ? "Back" : "Cancel",
                     variant: wizard.firstRun && !wizard.canGoBack ? .outline : .ghost) { onClose() }
            Spacer()
            if wizard.stage == .review {
                DMButton(wizard.firstRun ? "Run the setup" : "Create machine", systemImage: "play.fill") {
                    confirming = true
                }
                .keyboardShortcut(.defaultAction)
            } else if wizard.stage != .kind {
                DMButton("Continue") { state.wizard.next() }
                    .disabled(!wizard.canAdvance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Beside the form, before the run: what the answers so far make, and the
/// commands they would run, updated as the person types. The run screen puts
/// its log and step list in the same place.
struct AddMachineSummaryView: View {
    @Environment(\.dmMetrics) private var m
    let wizard: MachineWizard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: m.space.lg) {
                AddMachineFieldLabel(text: wizard.firstRun ? "Your setup" : "Your machine")
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: m.space.lg, verticalSpacing: m.space.sm) {
                    ForEach(wizard.summary, id: \.label) { row in
                        GridRow {
                            Text(verbatim: row.label)
                                .font(.dm(11))
                                .foregroundStyle(Color.dmMuted)
                            Text(verbatim: row.value)
                                .font(.dm(11.5, weight: .medium))
                                .foregroundStyle(Color.dmRowText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(m.space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dmSurface(Color.dmBand, radius: DMRadius.panel)
                if wizard.stage != .review {
                    AddMachineFieldLabel(text: "What will run")
                    let commands = wizard.previewCommands
                    if commands.isEmpty {
                        Text(verbatim: "The commands show here as you answer.")
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                    } else {
                        DMCommandBlock(commands, wraps: true)
                    }
                }
            }
        }
    }
}

private struct AddMachineKindView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel

    private var wizard: MachineWizard { state.wizard }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: wizard.firstRun ? "Do you already have a server (VPS)?" : "What are you adding?")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            HStack(alignment: .top, spacing: m.space.lg) {
                DMChoiceCard(
                    title: wizard.firstRun ? "Yes, I have a server" : "A server I have", systemImage: "server.rack",
                    detail: "A VPS or any Debian, Ubuntu, Arch Linux or macOS machine you reach by IP or hostname.",
                    selected: wizard.draft.kind == .server && wizard.stage != .kind
                ) { state.wizard.choose(.server) }
                DMChoiceCard(
                    title: wizard.firstRun ? "No, make a machine on this Mac" : "A machine on this Mac",
                    systemImage: "desktopcomputer",
                    detail: AddMachineContent.localChoiceDetail(limaFound: wizard.limaFound, unattended: wizard.unattended),
                    badge: wizard.firstRun ? "NO SERVER NEEDED" : nil,
                    selected: false
                ) { state.wizard.choose(.localVM) }
                .disabled(!wizard.canChoose(.localVM))
            }
            .fixedSize(horizontal: false, vertical: true)
            if !wizard.canChoose(.localVM) {
                VStack(alignment: .leading, spacing: m.space.sm) {
                    Text(verbatim: "A machine on this Mac needs Lima. Install it, then check again.")
                        .font(.dm(11.5))
                        .foregroundStyle(Color.dmMuted)
                    DMCommandBlock(LimaTool.installCommand)
                    DMButton("Check again", variant: .outline, size: .small) { state.refreshContext() }
                }
            }
        }
    }
}

struct AddMachineDetailsView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel

    private var draft: Binding<MachineDraft> { $state.wizard.draft }
    private var problems: [MachineDraftProblem] { state.wizard.problems }
    private var unattended: Bool { state.wizard.unattended }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            field("Name", .name, hint: "How every command names it, like main or lab.") {
                TextField("main", text: draft.name).dmField()
            }
            locationField
            if state.wizard.draft.kind == .server {
                serverFields
            } else {
                AddMachineNote(text: AddMachineContent.localNote(unattended: unattended))
                localSizeFields
            }
            workspaceField
            if unattended, !state.wizard.draft.hasConfiguration, state.wizard.draft.kind == .server {
                field("Domain", .domain,
                      hint: "Optional. Published sites get names under it, like app.example.com.") {
                    TextField("example.com", text: draft.domain).dmField()
                }
            }
            if !state.wizard.draft.hasConfiguration {
                AddMachineNote(text: unattended
                    ? "Your first machine also writes devmachine's configuration."
                    : "Your first machine goes through devmachine setup, in a terminal on the last step.")
            }
        }
    }

    private var locationField: some View {
        field("Where is it?", .location, hint: state.wizard.takesLocation
            ? "Machines in one place share a zone on the network map."
            : "Your CLI does not keep a location yet; it is kept once the CLI is updated.") {
            MachineLocationField(
                location: draft.location, known: state.knownLocations,
                defaultLocation: MachineLocation.defaultLocation(for: state.wizard.draft.kind))
        }
    }

    @ViewBuilder
    private var serverFields: some View {
        field("Address", .address, hint: "An IP, a hostname, or tailscale:<name>.") {
            TextField("203.0.113.10", text: draft.address).dmField()
        }
        HStack(alignment: .top, spacing: m.space.lg) {
            field("Admin login", .user, hint: "root, or an account with sudo and no password.") {
                TextField("root", text: draft.user).dmField()
            }
            field("SSH port", .port, hint: "Usually 22.") {
                TextField("22", text: draft.port).dmField()
            }
            .frame(width: m.pt(160))
        }
        VStack(alignment: .leading, spacing: m.space.sm) {
            label("Log in with")
            DMTabStrip(
                tabs: [ServerLogin.password, .key], selection: draft.login,
                title: { $0 == .key ? "SSH key" : "Password" },
                fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
        }
        if unattended {
            if state.wizard.draft.login == .key {
                keyChoice
            }
            passwordField
            AddMachineScanView(state: state)
        } else if state.wizard.draft.login == .key {
            keyFileField
            fingerprintField
        } else {
            AddMachineNote(text: "The CLI asks for the password in the terminal on the last step.")
            fingerprintField
        }
        passwordLoginFields
    }

    /// What happens to SSH password login once the key works. Off for every
    /// account is the default; on a Mac that is every account on it.
    @ViewBuilder
    private var passwordLoginFields: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            label("SSH password login, once the key works")
            DMTabStrip(
                tabs: state.wizard.passwordLoginChoices, selection: draft.passwordLogin,
                title: { $0.title }, fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
            Text(verbatim: AddMachineContent.passwordLoginHint)
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if state.wizard.draft.passwordLogin == .keepSome {
            field("Accounts that keep their password", .passwordLogin,
                  hint: "Separated by commas. Every other account logs in with a key only.") {
                TextField("alice, bob", text: draft.keepPasswordLoginAccounts).dmField()
            }
        }
    }

    /// The Lima machine's size, from what this Mac has; a CLI without the
    /// size flags makes it at its own default, and says so.
    @ViewBuilder
    private var localSizeFields: some View {
        if let limits = state.wizard.sizeLimits, state.wizard.draft.localSize != nil {
            VStack(alignment: .leading, spacing: m.space.sm) {
                label("Size")
                HStack(alignment: .top, spacing: m.space.md) {
                    sizeStepper(
                        "CPUs", value: sizeBinding(\.cpus), range: limits.cpus, step: 1, unit: "",
                        hint: "This Mac has \(limits.cpus.upperBound).")
                    sizeStepper(
                        "Memory", value: sizeBinding(\.memoryGiB), range: limits.memoryGiB, step: 1, unit: " GiB",
                        hint: "Up to \(limits.memoryGiB.upperBound) GiB: macOS keeps the rest.")
                    sizeStepper(
                        "Disk", value: sizeBinding(\.diskGiB), range: limits.diskGiB, step: 5, unit: " GiB",
                        hint: "Grows as it fills, up to \(limits.diskGiB.upperBound) GiB.")
                }
                if let problem = problems.first(where: { $0.field == .size }) {
                    warning(problem.message)
                }
            }
        } else if unattended {
            AddMachineNote(text: AddMachineContent.defaultSizeNote)
        }
    }

    private func sizeBinding(_ keyPath: WritableKeyPath<LocalMachineSize, Int>) -> Binding<Int> {
        Binding(
            get: { state.wizard.draft.localSize?[keyPath: keyPath] ?? 0 },
            set: { state.wizard.draft.localSize?[keyPath: keyPath] = $0 })
    }

    private func sizeStepper(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: m.space.xs) {
            Text(verbatim: title)
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            Stepper(value: value, in: range, step: step) {
                Text(verbatim: "\(value.wrappedValue)\(unit)")
                    .font(.dm(14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.dmRowText)
            }
            Text(verbatim: hint)
                .font(.dm(10.5))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(m.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }

    /// The first run makes a workspace unless the person turns it off, so the
    /// app opens with one in the sidebar; adding a machine later needs none.
    @ViewBuilder
    private var workspaceField: some View {
        let firstRun = state.wizard.firstRun
        VStack(alignment: .leading, spacing: m.space.md) {
            if firstRun {
                Toggle(isOn: Binding(
                    get: { !state.wizard.draft.skipsWorkspace },
                    set: { state.wizard.draft.skipsWorkspace = !$0 })
                ) {
                    Text(verbatim: "Make my first workspace now")
                        .font(.dm(12, weight: .medium))
                        .foregroundStyle(Color.dmRowText)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            if state.wizard.draft.skipsWorkspace, firstRun {
                AddMachineNote(text: AddMachineContent.noWorkspaceNote)
            } else {
                field(firstRun ? "First workspace" : "First workspace (optional)", .workspace,
                      hint: AddMachineContent.workspaceHint) {
                    TextField("acme", text: draft.workspace).dmField()
                }
            }
        }
    }

    private var keyFileField: some View {
        field("Key file", .keyFile, hint: "Like ~/.ssh/id_ed25519.") {
            TextField("~/.ssh/id_ed25519", text: draft.keyFile).dmField()
        }
    }

    /// Always shown on a CLI that takes it on stdin: a key not on the
    /// server yet needs it once, and a password login needs it every run.
    private var passwordField: some View {
        let key = state.wizard.draft.login == .key
        return field(key ? "Password (optional)" : "Password", .password,
                     hint: key ? AddMachineContent.keyPasswordHint : "It goes to the CLI once and is never saved.") {
            SecureField(key ? "Leave empty if the key already logs in" : "The server's password",
                        text: draft.password.value).dmField()
        }
    }

    @ViewBuilder
    private var keyChoice: some View {
        DMTabStrip(
            tabs: [ServerKeySource.agent, .file], selection: draft.keySource,
            title: { $0 == .file ? "Key file" : "SSH agent or 1Password" },
            fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
        if state.wizard.draft.keySource == .file {
            ForEach(state.keyFiles, id: \.self) { file in
                DMChoiceCard(
                    title: (file as NSString).lastPathComponent, detail: file,
                    selected: state.wizard.draft.keyFile == file
                ) {
                    state.wizard.draft.keyFile = file
                }
            }
            keyFileField
                .onAppear { state.loadKeyFiles() }
        } else {
            AddMachineAgentKeysView(state: state)
        }
    }

    private var fingerprintField: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            label(state.wizard.draft.login == .key ? "Server fingerprint" : "Server fingerprint (optional)")
            Text(verbatim: "Open the server's console in your provider's dashboard (not SSH), run this, "
                + "and paste what it prints. The CLI trusts the server only if its key matches.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            DMCommandBlock(AddMachineContent.verifyCommand)
            TextField(
                "256 SHA256:… root@server (ED25519)", text: draft.fingerprint, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: m.pt(11.5), design: .monospaced))
                .dmField()
            if let expected = state.wizard.draft.expectedFingerprint {
                Label { Text(verbatim: expected) } icon: { Image(systemName: "checkmark.seal.fill") }
                    .font(.dm(11))
                    .foregroundStyle(Color.green)
            } else if let problem = problems.first(where: { $0.field == .fingerprint }),
                      !state.wizard.draft.fingerprint.isEmpty {
                warning(problem.message)
            }
        }
    }

    private func field<Content: View>(
        _ title: String, _ field: MachineDraftField, hint: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: m.space.xs) {
            label(title)
            content()
            if let problem = problems.first(where: { $0.field == field }), touched(field) {
                warning(problem.message)
            } else {
                Text(verbatim: hint)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// An empty required field says what it wants by its hint; the warning
    /// is for something typed that the CLI would refuse.
    private func touched(_ field: MachineDraftField) -> Bool {
        let draft = state.wizard.draft
        switch field {
        case .name: return !draft.name.isEmpty
        case .address: return !draft.address.isEmpty
        case .keyFile: return !draft.keyFile.isEmpty
        case .workspace: return !draft.workspace.isEmpty
        default: return true
        }
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(11, weight: .semibold))
            .foregroundStyle(Color.dmRowText.opacity(0.8))
    }

    private func warning(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(11))
            .foregroundStyle(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AddMachinePackagesView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel
    let cards: [MachinePackageCard]

    private var shown: [MachinePackageCard] {
        cards.isEmpty ? [AddMachineContent.essentialsCard] : cards
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: "What goes on \(state.wizard.draft.name)?")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: m.pt(240)), spacing: m.space.md, alignment: .top)],
                alignment: .leading, spacing: m.space.md
            ) {
                ForEach(shown) { card in
                    DMChoiceCard(
                        title: card.name, detail: card.summary,
                        badge: badge(card),
                        note: card.contains.isEmpty ? nil : "Includes " + card.contains.joined(separator: ", ") + ".",
                        selected: state.wizard.isSelected(card.name), multiple: true, locked: card.isLocked
                    ) { state.wizard.togglePackage(card.name) }
                }
            }
            if cards.isEmpty {
                AddMachineNote(text: "The other packages are listed once your first machine exists: "
                    + "add them later with devmachine packages add.")
            }
            if state.wizard.firstRun {
                AddMachineSkillsChoice(state: state)
            } else {
                Toggle(isOn: $state.wizard.draft.sync) {
                    VStack(alignment: .leading, spacing: m.space.xxs) {
                        Text(verbatim: "Install them now")
                            .font(.dm(12, weight: .medium))
                            .foregroundStyle(Color.dmRowText)
                        Text(verbatim: "Runs devmachine sync at the end.")
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private func badge(_ card: MachinePackageCard) -> String? {
        if card.isLocked { return "ALWAYS INSTALLED" }
        if MachinePackageCatalog.suggestedPackages.contains(card.name) { return "SUGGESTED" }
        return card.isYours ? "YOURS" : nil
    }
}

/// The coding harnesses the devmachine skills are linked for. The skills
/// always install; this only says which harnesses see them.
private struct AddMachineSkillsChoice: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            AddMachineFieldLabel(text: "Your coding agents learn devmachine")
            Text(verbatim: "The setup installs the devmachine skills into ~/.agents/skills, then links them for "
                + "the agents chosen here. Preselected: the ones this Mac uses.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: DMSpace.sm) {
                ForEach(state.wizard.skillAgentOptions) { agent in
                    DMChip(title: agent.name, selected: state.wizard.draft.skillAgents.contains(agent)) {
                        state.wizard.toggleSkillAgent(agent.id)
                    }
                }
            }
            if state.wizard.draft.skillAgents.isEmpty {
                AddMachineNote(text: "No agent chosen: the skills are not installed. "
                    + "Run devmachine skills add later to add them.")
            }
        }
    }
}

struct AddMachineReviewView: View {
    @Environment(\.dmMetrics) private var m
    let wizard: MachineWizard

    private var draft: MachineDraft { wizard.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: wizard.unattended
                ? "These run in order on the next step, here, with every log shown."
                : "These commands run in order, in a terminal on the next step.")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
            ForEach(wizard.plan.filter { !$0.isCommand }) { step in
                AddMachineNote(text: "First: " + step.displayLine + ".")
            }
            DMCommandBlock(wizard.plan.filter(\.isCommand).map(\.displayLine), wraps: true)
            if draft.kind == .localVM, let size = wizard.sizeToCreate {
                AddMachineNote(text: "\(draft.trimmedName) gets \(size.summary).")
            }
            if wizard.plan.contains(where: { $0.input == .password }) {
                AddMachineNote(text: "The password goes to the CLI on its standard input, never in a file or log.")
            }
            let answers = wizard.terminalAnswers
            if !answers.isEmpty {
                Text(verbatim: "The CLI asks some questions itself. Answer them in the terminal:")
                    .font(.dm(12))
                    .foregroundStyle(Color.dmMuted)
                AddMachineAnswers(answers: answers)
            }
            AddMachineNote(text: AddMachineContent.reviewNote(draft, firstRun: wizard.firstRun))
        }
    }
}

struct AddMachineRunView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel
    @ObservedObject var runner: MachineStepRunner
    let onClose: () -> Void

    var body: some View {
        MachineRunLayout(
            steps: state.wizard.plan, runner: runner, inTerminal: !state.wizard.unattended,
            answers: runner.phase == .succeeded ? [] : state.wizard.terminalAnswers
        ) {
            outcome
        }
    }

    @ViewBuilder
    private var outcome: some View {
        if state.onlySkillsFailed {
            succeeded
            SetupFailurePanel(
                step: state.failedStep, lines: runner.lines, problem: runner.problem, exitCode: runner.exitCode,
                onRetry: { Task { await state.retry() } })
        } else {
            switch runner.phase {
            case .succeeded:
                succeeded
            case .failed:
                let asksPassword = state.retryField == .password
                SetupFailurePanel(
                    step: state.failedStep, lines: runner.lines, problem: runner.problem, exitCode: runner.exitCode,
                    onRetry: state.canRetry && !asksPassword ? { Task { await state.retry() } } : nil,
                    onEditAnswers: { state.editAnswers() })
                if asksPassword {
                    AddMachinePasswordRetry(state: state)
                }
                if state.offersHomebrewLima {
                    DMButton("Install Lima with Homebrew instead", systemImage: "shippingbox", variant: .outline,
                             size: .small) { Task { await state.retryLimaWithHomebrew() } }
                }
                if !state.canRetry, !asksPassword {
                    Text(verbatim: "The password is not kept after a run. Type it again to try again.")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !state.wizard.firstRun {
                    DMButton("Close", variant: .ghost, size: .small, action: onClose)
                }
            case .running, .idle:
                Text(verbatim: state.wizard.unattended
                    ? "Each step's log shows on the left as it runs. Nothing here asks a question."
                    : "Watch the terminal. A step that asks something waits for you there.")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if runner.phase == .running {
                    DMButton("Stop", systemImage: "stop.fill", variant: .dangerOutline, size: .small) { state.stop() }
                }
            }
        }
    }

    @ViewBuilder
    private var succeeded: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Label {
                Text(verbatim: "\(state.wizard.draft.name) is ready")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
            }
            .font(.dm(14, weight: .semibold))
            .foregroundStyle(Color.dmRowText)
            if !state.wizard.firstRun {
                Text(verbatim: state.wizard.draft.trimmedWorkspace.isEmpty
                    ? "It is in Settings → Machines. Add a workspace to see it in the sidebar."
                    : "The workspace \(state.wizard.draft.trimmedWorkspace) shows in the sidebar.")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                DMButton("Done", action: onClose)
            }
        }
    }
}

/// The password asked right on a failed add, for one Try again: it goes to
/// the CLI's stdin like the one typed in the details, and is not kept.
struct AddMachinePasswordRetry: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel
    @State private var password = SecretText()

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            SecureField("The server's password", text: $password.value)
                .dmField()
                .onSubmit(retry)
            DMButton("Try again with this password", systemImage: "arrow.clockwise", action: retry)
                .disabled(password.value.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .onDisappear { password = SecretText() }
    }

    private func retry() {
        guard !password.value.isEmpty else { return }
        let typed = password
        password = SecretText()
        Task { await state.retry(password: typed) }
    }
}

/// A run on screen: the log (or the terminal, for an older CLI) on the
/// left, and beside it how it ends and every step with its command.
struct MachineRunLayout<Outcome: View>: View {
    @Environment(\.dmMetrics) private var m
    let steps: [MachinePlanStep]
    @ObservedObject var runner: MachineStepRunner
    var inTerminal = false
    var answers: [MachinePlan.Answer] = []
    @ViewBuilder let outcome: () -> Outcome

    var body: some View {
        HStack(alignment: .top, spacing: m.space.xl) {
            if inTerminal {
                TerminalPaneView(kind: runner.terminalKind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dmSurface(Color.black, radius: DMRadius.panel)
            } else {
                DMLogView(lines: runner.lines, fills: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: m.space.lg) {
                    outcome()
                    stepList
                    if !answers.isEmpty {
                        Text(verbatim: "When the terminal asks")
                            .font(.dm(11, weight: .semibold))
                            .foregroundStyle(Color.dmRowText.opacity(0.8))
                        AddMachineAnswers(answers: answers)
                    }
                }
            }
            .frame(width: m.pt(AddMachineContent.sideWidth))
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            ForEach(steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: m.space.md) {
                    icon(runner.status(of: step))
                        .frame(width: m.pt(DMIconSize.md))
                    VStack(alignment: .leading, spacing: m.space.xxs) {
                        Text(verbatim: step.title)
                            .font(.dm(12, weight: .medium))
                            .foregroundStyle(Color.dmRowText)
                        Text(verbatim: step.displayLine)
                            .font(.dm(10, design: .monospaced))
                            .foregroundStyle(Color.dmMuted)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if let attempt = runner.attemptLabel(of: step) {
                            Text(verbatim: attempt)
                                .font(.dm(10.5))
                                .foregroundStyle(Color.dmMuted)
                        }
                        if step.asksInTerminal {
                            Text(verbatim: "Asks in the terminal")
                                .font(.dm(10.5))
                                .foregroundStyle(Color.dmMuted)
                        }
                    }
                }
            }
        }
        .padding(m.space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }

    @ViewBuilder
    private func icon(_ status: MachineStepRunner.StepStatus) -> some View {
        switch status {
        case .waiting: Image(systemName: "circle").foregroundStyle(Color.dmMuted)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red)
        }
    }
}

private struct AddMachineAnswers: View {
    @Environment(\.dmMetrics) private var m
    let answers: [MachinePlan.Answer]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: m.space.lg, verticalSpacing: m.space.sm) {
            ForEach(answers, id: \.question) { answer in
                GridRow {
                    Text(verbatim: answer.question)
                        .font(.dm(11.5))
                        .foregroundStyle(Color.dmMuted)
                    Text(verbatim: answer.answer)
                        .font(.dm(11.5, design: .monospaced))
                        .foregroundStyle(Color.dmRowText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(m.space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }
}

struct AddMachineNote: View {
    @Environment(\.dmMetrics) private var m
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.dm(11))
        .foregroundStyle(Color.dmMuted)
    }
}

enum AddMachineContent {
    /// The column beside a run's log, and beside the wizard's form before it.
    static let sideWidth: CGFloat = 340

    /// The ed25519 key is what the CLI prefers, and what ssh offers first.
    static let verifyCommand = "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"

    static let essentialsCard = MachinePackageCard(
        name: MachinePackageCatalog.essentials,
        summary: "What a new machine starts with: base tools, git, a firewall, SSH without passwords, "
            + "Caddy, and what this app reads from a machine.",
        isRecommended: true, isYours: false)

    static let defaultSizeNote = "This devmachine CLI makes the machine at its own size: 2 CPUs, 4 GiB of "
        + "memory, a 20 GiB disk. Version \(LocalMachineSizing.minimumCLIVersion) or newer lets you choose it here."

    static let passwordLoginHint = "One setting for every account on the machine; on a Mac, that is everyone "
        + "who logs in to it over SSH."

    static let keyPasswordHint = "Needed once, to put the key on the server. Leave empty if the key already logs in."

    static let workspaceHint = "The account your sessions run in, named after your project, like acme."

    static let noWorkspaceNote = "Until you add a workspace, sessions run only on this Mac."

    static func localNote(unattended: Bool) -> String {
        unattended
            ? "Lima makes the machine on this Mac, and devmachine connects it: there is nothing to type."
            : "Lima makes the machine on this Mac; the next step adds it like a server."
    }

    static func localChoiceDetail(limaFound: Bool, unattended: Bool) -> String {
        var text = "A Lima virtual machine to try devmachine with no server. "
            + "Nothing on the internet can reach it, so it cannot publish sites."
        if !limaFound, unattended {
            text += " Lima is installed first, from its GitHub release (no Homebrew needed)."
        }
        return text
    }

    static func confirmMessage(_ draft: MachineDraft) -> String {
        switch draft.kind {
        case .localVM:
            return "Lima creates a virtual machine on this Mac, then devmachine sets it up and installs "
                + "what you chose. It takes a few minutes."
        case .server:
            return "devmachine connects to \(draft.address), installs a key, \(draft.passwordLoginPhrase), "
                + "installs Ansible\(draft.sync ? " and the packages you chose" : ""). "
                + "Nothing else on the server is changed."
        }
    }

    static func reviewNote(_ draft: MachineDraft, firstRun: Bool = false) -> String {
        let installs = firstRun || draft.sync
        switch draft.kind {
        case .localVM:
            return installs ? "This takes a few minutes the first time." : "Nothing is installed until you sync."
        case .server:
            return "The first command puts a key on the server and \(draft.passwordLoginPhrase)."
        }
    }
}
