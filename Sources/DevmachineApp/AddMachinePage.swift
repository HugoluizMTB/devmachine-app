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
        if model.activePage == .addMachine { model.activePage = nil }
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
                ScrollView {
                    stageBody
                        .frame(maxWidth: m.pt(760), alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
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
        .frame(maxWidth: m.pt(760))
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
                    detail: "A VPS or any Debian or Ubuntu server you reach by IP or hostname.",
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
            if state.wizard.draft.kind == .server {
                serverFields
            } else {
                AddMachineNote(text: AddMachineContent.localNote(unattended: unattended))
            }
            if !state.wizard.firstRun {
                field("First workspace", .workspace,
                      hint: "Optional. A workspace is one Linux account on the machine, and what the sidebar lists.") {
                    TextField("acme", text: draft.workspace).dmField()
                }
            }
            if unattended, !state.wizard.draft.hasConfiguration, state.wizard.draft.kind == .server {
                field("Domain", .domain,
                      hint: "Optional. Published sites get names under it, like app.example.com.") {
                    TextField("example.com", text: draft.domain).dmField()
                }
            }
            if !state.wizard.draft.hasConfiguration {
                AddMachineNote(text: unattended
                    ? "This is your first machine, so adding it also writes devmachine's configuration, "
                        + "as devmachine setup would. Nothing asks in a terminal."
                    : "This is your first machine, so devmachine setup adds it. "
                        + "It asks its questions in the terminal on the last step; the answers to give are shown there.")
            }
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
            label("How does the server let you in today?")
            DMTabStrip(
                tabs: ServerLogin.allCases, selection: draft.login,
                title: { $0 == .key ? "With an SSH key" : "Only with a password" },
                fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
        }
        if unattended {
            if state.wizard.draft.login == .key {
                keyChoice
            } else {
                field("Password", .password,
                      hint: "Goes to the CLI on its standard input, once, to install a key; then password login "
                        + "is turned off. It is never saved, logged or put in a command line.") {
                    SecureField("The root password from your provider", text: draft.password.value).dmField()
                }
            }
            AddMachineScanView(state: state)
        } else if state.wizard.draft.login == .key {
            keyFileField
            fingerprintField
        } else {
            AddMachineNote(text: "The CLI asks for the password in the terminal on the last step, "
                + "uses it once to install a key, then turns password login off. The app never sees it.")
            fingerprintField
        }
    }

    private var keyFileField: some View {
        field("Key file", .keyFile,
              hint: "The private key you gave your provider for this server, like ~/.ssh/id_ed25519. "
                + "No key on it yet? Choose \"Only with a password\".") {
            TextField("~/.ssh/id_ed25519", text: draft.keyFile).dmField()
        }
    }

    @ViewBuilder
    private var keyChoice: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            label("Which key?")
            DMTabStrip(
                tabs: ServerKeySource.allCases, selection: draft.keySource,
                title: { $0 == .file ? "A key file" : "A key in the SSH agent" },
                fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
        }
        if state.wizard.draft.keySource == .file {
            keyFileField
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
                        Text(verbatim: "Runs devmachine sync at the end. Off, the packages are only written "
                            + "to the configuration until you sync.")
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
            FlowLayout(spacing: m.space.sm) {
                ForEach(SkillAgent.all) { agent in
                    DMChip(title: agent.name, selected: state.wizard.draft.skillAgents.contains(agent.id)) {
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
            if wizard.plan.contains(where: { $0.input == .password }) {
                AddMachineNote(text: "The password goes to the CLI on its standard input. "
                    + "It is never in a command line, a file or a log.")
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
                SetupFailurePanel(
                    step: state.failedStep, lines: runner.lines, problem: runner.problem, exitCode: runner.exitCode,
                    onRetry: state.canRetry ? { Task { await state.retry() } } : nil,
                    onEditAnswers: { state.editAnswers() })
                if state.offersHomebrewLima {
                    DMButton("Install Lima with Homebrew instead", systemImage: "shippingbox", variant: .outline,
                             size: .small) { Task { await state.retryLimaWithHomebrew() } }
                }
                if !state.canRetry {
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
                Text(verbatim: state.wizard.draft.workspace.isEmpty
                    ? "It is in Settings → Machines. Add a workspace to see it in the sidebar."
                    : "Its workspace shows in the sidebar.")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                DMButton("Done", action: onClose)
            }
        }
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
            .frame(width: m.pt(340))
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

private struct AddMachineNote: View {
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
    /// The ed25519 key is what the CLI prefers, and what ssh offers first.
    static let verifyCommand = "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"

    static let essentialsCard = MachinePackageCard(
        name: MachinePackageCatalog.essentials,
        summary: "What a new machine starts with: base tools, git, a firewall, SSH without passwords, "
            + "Caddy, and what this app reads from a machine.",
        isRecommended: true, isYours: false)

    static func localNote(unattended: Bool) -> String {
        unattended
            ? "Lima creates the machine with root and the password devmachine, public on purpose: it holds "
                + "nothing real. devmachine then connects it with that password and turns password login off. "
                + "No address to type: it runs on this Mac."
            : "Lima creates the machine with root and the password devmachine, "
                + "public on purpose: it holds nothing real. The next step adds it like a server you bought."
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
            return "devmachine connects to \(draft.address), installs a key, turns password login off, "
                + "installs Ansible\(draft.sync ? " and the packages you chose" : ""). "
                + "Nothing else on the server is changed."
        }
    }

    static func reviewNote(_ draft: MachineDraft, firstRun: Bool = false) -> String {
        let sync = firstRun || draft.sync
            ? " sync then installs the packages." : " Nothing is installed until you run devmachine sync."
        let retry = " If a step fails, Retry starts again from that step."
        switch draft.kind {
        case .localVM:
            return "create-local takes a few minutes the first time." + sync + retry
        case .server:
            return "The first command changes the server: a key goes in and password login goes off. "
                + "The package commands only write the configuration on this Mac." + sync + retry
        }
    }
}
