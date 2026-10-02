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
            scanMachine: { address, port in DemoData.addMachineScan(address: address, port: port) },
            listAgentKeys: { DemoData.addMachineAgentKeys })
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
    private let onAdded: @MainActor () -> Void
    private let scanMachine: @Sendable (String, String) async throws -> MachineScan
    private let listAgentKeys: @Sendable () async throws -> [AgentKey]

    init(
        machines: MachinesStore = .shared,
        runner: MachineStepRunner = MachineStepRunner(),
        findLima: @escaping () -> String? = { LimaTool.find() },
        onAdded: @escaping @MainActor () -> Void = { AddMachineModel.reloadEverything() },
        scanMachine: @escaping @Sendable (String, String) async throws -> MachineScan = { address, port in
            try await Task.detached { try DevmachineCLI.resolve().scanMachine(address: address, port: port) }.value
        },
        listAgentKeys: @escaping @Sendable () async throws -> [AgentKey] = {
            try await Task.detached { try DevmachineCLI.resolve().agentKeys() }.value
        }
    ) {
        self.machines = machines
        self.runner = runner
        self.findLima = findLima
        self.onAdded = onAdded
        self.scanMachine = scanMachine
        self.listAgentKeys = listAgentKeys
        wizard = MachineWizard(existingMachines: [], limaFound: false)
        startOver()
    }

    var isRunning: Bool { runner.phase == .running }

    /// A fresh wizard, unless a run is going or ended in a failure to read.
    func openPage() {
        guard !isRunning else { return }
        if wizard.stage == .run, runner.phase == .succeeded { startOver() }
        if wizard.stage != .run { refreshContext() }
    }

    func startOver() {
        runner.reset()
        scanError = nil
        wizard = freshWizard()
    }

    /// The answers stay; what the configuration holds and whether Lima is
    /// there are read again, since either may have changed meanwhile.
    func refreshContext() {
        let draft = wizard.draft
        let stage = wizard.stage
        var next = freshWizard()
        let hasConfiguration = next.draft.hasConfiguration
        next.draft = draft
        next.draft.hasConfiguration = hasConfiguration
        next.restore(stage)
        wizard = next
    }

    private func freshWizard() -> MachineWizard {
        var wizard = MachineWizard(
            existingMachines: machines.machines.map(\.name), limaFound: DemoMode.isActive || findLima() != nil,
            unattended: machines.snapshot?.addsWithoutTerminal ?? false)
        wizard.draft.hasConfiguration = machines.snapshot?.hasConfiguration ?? true
        return wizard
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
    /// failed step simply runs again.
    func retry() async {
        await runPlan()
    }

    private func runPlan() async {
        await runner.run(wizard.plan, inTerminal: !wizard.unattended, password: wizard.draft.password)
        guard runner.phase == .succeeded else { return }
        wizard.draft.password = SecretText()
        onAdded()
    }

    static func reloadEverything() {
        MachinesStore.shared.requestLoad()
        MachineReadinessStore.shared.requestCheck()
        AppModel.shared?.reloadConfiguration()
    }
}
