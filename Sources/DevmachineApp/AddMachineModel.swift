import Foundation
import DevmachineCore

/// The Add machine page's state, kept for the app's life so leaving the page
/// mid-run (to look at Home, a session) and coming back finds the run where
/// it was, with the same terminal.
@MainActor
final class AddMachineModel: ObservableObject {
    static let shared = AddMachineModel()

    @Published var wizard: MachineWizard
    let runner: MachineStepRunner
    private let machines: MachinesStore
    private let findLima: () -> String?
    private let onAdded: @MainActor () -> Void

    init(
        machines: MachinesStore = .shared,
        runner: MachineStepRunner = MachineStepRunner(),
        findLima: @escaping () -> String? = { LimaTool.find() },
        onAdded: @escaping @MainActor () -> Void = { AddMachineModel.reloadEverything() }
    ) {
        self.machines = machines
        self.runner = runner
        self.findLima = findLima
        self.onAdded = onAdded
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
        wizard = MachineWizard(
            existingMachines: machines.machines.map(\.name), limaFound: DemoMode.isActive || findLima() != nil)
        wizard.draft.hasConfiguration = machines.snapshot?.hasConfiguration ?? true
    }

    /// The answers stay; what the configuration holds and whether Lima is
    /// there are read again, since either may have changed meanwhile.
    func refreshContext() {
        let draft = wizard.draft
        let stage = wizard.stage
        var next = MachineWizard(
            existingMachines: machines.machines.map(\.name), limaFound: DemoMode.isActive || findLima() != nil)
        next.draft = draft
        next.draft.hasConfiguration = machines.snapshot?.hasConfiguration ?? true
        next.restore(stage)
        wizard = next
    }

    func create() async {
        wizard.next()
        await runner.run(wizard.plan)
        if runner.phase == .succeeded { onAdded() }
    }

    func retry() async {
        await runner.run(wizard.plan)
        if runner.phase == .succeeded { onAdded() }
    }

    static func reloadEverything() {
        MachinesStore.shared.requestLoad()
        MachineReadinessStore.shared.requestCheck()
        AppModel.shared?.reloadConfiguration()
    }
}
