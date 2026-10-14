import Foundation
import DevmachineCore

/// The Add machine page's state, kept for the app's life so leaving the page
/// mid-run (to look at Home, a session) and coming back finds the run where
/// it was, with the same terminal.
@MainActor
final class AddMachineModel: ObservableObject {
    /// Demo mode reads no server and no agent: it answers with invented keys.
    static let shared = DemoMode.isActive
        ? AddMachineModel(
            findLima: { "/opt/homebrew/bin/limactl" },
            scanMachine: { address, port in DemoData.addMachineScan(address: address, port: port) },
            listAgentKeys: { DemoData.addMachineAgentKeys },
            macLimits: { DemoData.macLimits })
        : AddMachineModel()

    @Published var wizard: MachineWizard
    @Published private(set) var scanning = false
    @Published private(set) var scanError: String?
    /// Nil until the agent was asked.
    @Published private(set) var agentKeys: [AgentKey]?
    @Published private(set) var agentKeysError: String?
    let runner: MachineStepRunner
    private let machines: MachinesStore
    private let findLima: () -> String?
    private let findBrew: () -> String?
    /// How the plan's Lima step installs it: the release first, Homebrew
    /// once that failed and the person asked for it.
    @Published private(set) var limaMethod: LimaInstall.Method = .release
    /// Onboarding's own wizard sets it to move to its next step.
    var onAdded: @MainActor () -> Void
    /// The first-run setup: the same wizard, ending with this app's package,
    /// a sync and the skills.
    let firstRun: Bool
    /// The harnesses the skills are linked for at first, out of the options:
    /// the ones in use on this Mac.
    private let skillAgents: ([SkillAgent]) -> [SkillAgent]
    /// What this Mac can give a Lima machine: its cores, memory and free disk.
    private let macLimits: () -> LocalMachineSizeLimits
    private let scanMachine: @Sendable (String, String) async throws -> MachineScan
    private let listAgentKeys: @Sendable () async throws -> [AgentKey]

    init(
        machines: MachinesStore = .shared,
        runner: MachineStepRunner = MachineStepRunner(),
        findLima: @escaping () -> String? = { LimaTool.find() },
        findBrew: @escaping () -> String? = { LimaInstaller.findBrew() },
        onAdded: @escaping @MainActor () -> Void = { AddMachineModel.reloadEverything() },
        scanMachine: @escaping @Sendable (String, String) async throws -> MachineScan = { address, port in
            try await Task.detached { try DevmachineCLI.resolve().scanMachine(address: address, port: port) }.value
        },
        listAgentKeys: @escaping @Sendable () async throws -> [AgentKey] = {
            try await Task.detached { try DevmachineCLI.resolve().agentKeys() }.value
        },
        skillAgents: @escaping ([SkillAgent]) -> [SkillAgent] = { AddMachineModel.harnessesInUse(from: $0) },
        macLimits: @escaping () -> LocalMachineSizeLimits = { AddMachineModel.thisMacLimits() },
        firstRun: Bool = false
    ) {
        self.macLimits = macLimits
        self.firstRun = firstRun
        self.skillAgents = skillAgents
        self.machines = machines
        self.runner = runner
        self.findLima = findLima
        self.findBrew = findBrew
        self.onAdded = onAdded
        self.scanMachine = scanMachine
        self.listAgentKeys = listAgentKeys
        wizard = MachineWizard(existingMachines: [], limaFound: false, firstRun: firstRun)
        startOver()
    }

    var isRunning: Bool { runner.phase == .running }

    var packageCards: [MachinePackageCard] { machines.packageCards }

    /// Where the configured machines already are, so a second machine at
    /// home is one click.
    var knownLocations: [String] {
        var seen = Set<String>()
        return machines.machines.map(\.location).filter { seen.insert($0).inserted }
    }

    /// The first-run setup's wizard. Demo mode scans no server and reads no agent.
    static func forOnboarding() -> AddMachineModel {
        guard DemoMode.isActive else { return AddMachineModel(firstRun: true) }
        let machines = MachinesStore(read: { DemoData.noMachinesSnapshot }, remove: { _ in })
        machines.seedDemo(DemoData.noMachinesSnapshot)
        return AddMachineModel(
            machines: machines,
            findLima: { nil }, findBrew: { "/opt/homebrew/bin/brew" },
            scanMachine: { address, port in DemoData.addMachineScan(address: address, port: port) },
            listAgentKeys: { DemoData.addMachineAgentKeys },
            skillAgents: { options in options.filter { [.claude, .codex].contains($0.harness) } },
            macLimits: { DemoData.macLimits },
            firstRun: true)
    }

    /// Reads the configuration, then starts a fresh wizard: whether it is
    /// the first machine and what the CLI can do decide what it asks.
    func prepareFirstRun() async {
        await machines.load()
        startOver()
    }

    static func thisMacLimits(home: String = NSHomeDirectory()) -> LocalMachineSizeLimits {
        let free = try? URL(fileURLWithPath: home)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        return LocalMachineSizeLimits(
            cores: ProcessInfo.processInfo.activeProcessorCount,
            memoryBytes: ProcessInfo.processInfo.physicalMemory, freeDiskBytes: free ?? nil)
    }

    /// The harnesses enabled in Settings → Coding agents, and the ones whose
    /// folder this Mac has (what `skills add` itself would find).
    static func harnessesInUse(from options: [SkillAgent], home: String = NSHomeDirectory()) -> [SkillAgent] {
        let enabled = AppModel.shared?.settings?.enabledHarnesses ?? []
        return SkillAgent.preselected(from: options, harnesses: enabled, home: home) { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Every harness the app knows that this CLI's `skills add` accepts.
    static func skillAgentOptions(
        cliVersion: SemanticVersion?, registry: HarnessRegistry = .builtIn
    ) -> [SkillAgent] {
        SkillAgent.options(
            harnesses: registry.adapters.map { ($0.id, $0.descriptor.title) }, cliVersion: cliVersion)
    }

    /// Only the skills step failed: the machine is set up, and a Retry
    /// installs them.
    var onlySkillsFailed: Bool {
        guard case .failed = runner.phase,
              let failed = wizard.plan.first(where: { runner.status(of: $0) == .failed })
        else { return false }
        return !failed.blocksSetup
    }

    /// The workspace the last run made, once its step is done: it is in the
    /// configuration now, and must not block the answers that made it.
    var madeWorkspace: String? {
        guard let step = wizard.plan.first(where: { $0.kind == .newWorkspace }),
              runner.status(of: step) == .done else { return nil }
        return wizard.draft.trimmedWorkspace
    }

    var failedStep: MachinePlanStep? {
        wizard.plan.first { runner.status(of: $0) == .failed }
    }

    /// Try again needs every answer the failed step reads; the password is
    /// forgotten after each run, so a step that reads it asks for it again.
    var canRetry: Bool {
        !wizard.plan.contains { $0.input == .password && runner.status(of: $0) != .done }
            || !wizard.draft.password.value.isEmpty
    }

    /// A fresh wizard after a success; the answers after a failure, at the
    /// first step that needs one; a run still going is left alone.
    func openPage() {
        guard !isRunning else { return }
        if wizard.stage == .run, runner.phase == .succeeded { startOver() }
        if wizard.stage != .run { refreshContext() }
    }

    /// The page went away (another page, a session, Close): the password
    /// never outlives it.
    func leavePage() {
        wizard.draft.password = SecretText()
    }

    /// Done or Close on the run screen, Cancel before it. A failed run goes
    /// back to its answers, so the page reopens on them, not on the error.
    func close() {
        leavePage()
        guard !isRunning, wizard.stage == .run else { return }
        if runner.phase == .succeeded {
            startOver()
        } else {
            editAnswers()
        }
    }

    func stop() {
        runner.stop()
    }

    /// Back from a failed or stopped run to its details, every answer kept.
    /// Steps already done stay done, so a second Create skips them.
    func editAnswers() {
        guard !isRunning, wizard.stage == .run else { return }
        wizard.editAnswers()
        refreshContext()
    }

    /// The Lima step failed with its release download and Homebrew is there.
    var offersHomebrewLima: Bool {
        guard limaMethod == .release, findBrew() != nil,
              let step = wizard.plan.first(where: { $0.kind == .installLima })
        else { return false }
        return runner.status(of: step) == .failed
    }

    func retryLimaWithHomebrew() async {
        guard let brew = findBrew() else { return }
        limaMethod = .homebrew(brew: brew)
        await retry()
    }

    func startOver() {
        limaMethod = .release
        runner.reset()
        scanError = nil
        wizard = freshWizard()
    }

    /// The answers stay, except the password; what the configuration holds
    /// and whether Lima is there are read again, since either may have
    /// changed meanwhile. A CLI that changed may need answers the older one
    /// did not, so the wizard stops at the first step that needs one.
    func refreshContext() {
        let draft = wizard.draft
        let stage = wizard.stage
        var next = freshWizard()
        let hasConfiguration = next.draft.hasConfiguration
        next.draft = draft
        next.draft.password = SecretText()
        next.draft.hasConfiguration = hasConfiguration
        if let limits = next.sizeLimits {
            next.draft.localSize = draft.localSize.map(limits.clamped) ?? limits.defaultSize
        }
        next.restore(stage)
        wizard = next
    }

    private func freshWizard() -> MachineWizard {
        let added = addedByThisRun
        let addedWorkspace = madeWorkspace
        var wizard = MachineWizard(
            existingMachines: machines.machines.map(\.name).filter { $0 != added },
            existingWorkspaces: machines.machines.flatMap(\.workspaces).filter { $0 != addedWorkspace },
            limaFound: findLima() != nil,
            unattended: machines.snapshot?.addsWithoutTerminal ?? false,
            firstRun: firstRun,
            sizeLimits: LocalMachineSizing.isSupported(cliVersion: machines.snapshot?.cliVersion) ? macLimits() : nil,
            skillAgentOptions: firstRun ? Self.skillAgentOptions(cliVersion: machines.snapshot?.cliVersion) : [],
            takesLocation: machines.snapshot?.takesLocation ?? false,
            takesKeepPasswordLogin: PasswordLoginChoice.keepIsSupported(cliVersion: machines.snapshot?.cliVersion))
        wizard.draft.localSize = wizard.sizeLimits?.defaultSize
        wizard.draft.hasConfiguration = machines.snapshot?.hasConfiguration ?? true
        wizard.draft.packages = MachinePackageCatalog.suggested(from: machines.packageCards)
        if firstRun { wizard.draft.skillAgents = skillAgents(wizard.skillAgentOptions) }
        return wizard
    }

    /// The machine this wizard's own run already wrote: it is in the
    /// configuration now, and must not block the answers that made it.
    private var addedByThisRun: String? {
        let creates = wizard.plan.first {
            ($0.kind == .addMachine || $0.kind == .createLocal) && runner.status(of: $0) == .done
        }
        return creates == nil ? nil : wizard.draft.name.trimmingCharacters(in: .whitespaces)
    }

    /// Reads the key the server presents (`machines scan`), which logs in
    /// nowhere and writes nothing, so the person can compare it with the
    /// provider's console before anything trusts it.
    func scan() async {
        let address = wizard.draft.address.trimmingCharacters(in: .whitespaces)
        let port = wizard.draft.port.trimmingCharacters(in: .whitespaces)
        guard !scanning, !address.isEmpty else { return }
        scanning = true
        scanError = nil
        defer { scanning = false }
        do {
            let scan = try await scanMachine(address, port)
            wizard.draft.scan = scan
            wizard.draft.scanConfirmed = false
        } catch {
            wizard.draft.scan = nil
            scanError = error.localizedDescription
        }
    }

    /// The keys the SSH agent holds, read again each time the agent choice
    /// is shown: a password manager may have been unlocked meanwhile.
    func loadAgentKeys() async {
        do {
            let keys = try await listAgentKeys()
            agentKeys = keys
            agentKeysError = nil
            if keys.count == 1, wizard.draft.agentKey.isEmpty { wizard.draft.agentKey = keys[0].fingerprint }
        } catch {
            agentKeys = []
            agentKeysError = error.localizedDescription
        }
    }

    func create() async {
        wizard.next()
        await runPlan()
    }

    /// `machines add` writes the machine only once its key is proved, so a
    /// failed step simply runs again. Without the password it needs, the
    /// answers open instead.
    func retry() async {
        guard canRetry else { return editAnswers() }
        await runPlan()
    }

    private func runPlan() async {
        let password = wizard.draft.password
        wizard.draft.password = SecretText()
        BugReportEnvironment.typedHosts = [wizard.draft.trimmedAddress]
        BugReportEnvironment.typedDomains = [wizard.draft.trimmedDomain]
        BugReportEnvironment.typedMachines = [wizard.draft.trimmedName]
        BugReportEnvironment.typedWorkspaces = [wizard.draft.workspace.trimmingCharacters(in: .whitespaces)]
        await runner.run(
            wizard.plan, inTerminal: !wizard.unattended, password: password, limaMethod: limaMethod,
            label: firstRun ? "Setting up devmachine…" : "Adding a machine…")
        guard runner.phase == .succeeded || onlySkillsFailed else { return }
        onAdded()
    }

    static func reloadEverything() {
        MachinesStore.shared.requestLoad()
        MachineReadinessStore.shared.requestCheck()
        AppModel.shared?.reloadConfiguration()
    }
}
