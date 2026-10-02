import Foundation
import DevmachineCore

/// Carries out what `OnboardingFlow` decides: runs the steps outside the
/// wizard in the background with their log (`prepare`), opens the wizard
/// (`wizard`), and reads the Mac again after each.
@MainActor
final class OnboardingRunner: ObservableObject {
    @Published private(set) var flow = OnboardingFlow()
    let wizard: AddMachineModel
    let prepare: MachineStepRunner

    private let detect: @Sendable () async -> OnboardingDetection
    private var detecting = false
    private var detectAgain = false

    init(
        detect: (@Sendable () async -> OnboardingDetection)? = nil,
        wizard: AddMachineModel? = nil,
        prepare: MachineStepRunner? = nil
    ) {
        self.wizard = wizard ?? AddMachineModel.forOnboarding()
        self.prepare = prepare ?? MachineStepRunner()
        self.detect = detect ?? Self.liveDetect
        self.wizard.onAdded = { [weak self] in self?.wizardFinished() }
    }

    /// Demo mode reads no CLI: it shows a Mac with nothing yet.
    private static let liveDetect: @Sendable () async -> OnboardingDetection = {
        guard !DemoMode.isActive else { return DemoSetupFlow.freshMac }
        return await Task.detached { OnboardingDetector.detect() }.value
    }

    /// Demo screenshots: a flow in any state, with nothing behind it.
    func seedDemo(_ flow: OnboardingFlow) {
        self.flow = flow
    }

    func start() { perform(flow.start()) }
    func checkAgain() { perform(flow.checkAgain()) }
    func updateCLI() { perform(flow.updateCLI()) }
    func back() { perform(flow.back()) }

    /// Runs the failed prepare step again; the ones already done are skipped.
    func retry() {
        guard case .failed = prepare.phase else { return }
        let steps = flow.plan
        Task { await runPrepare(steps) }
    }

    func stop() { prepare.stop() }

    /// The page is going away: whatever still runs ends with it.
    func leave() {
        prepare.stop()
        wizard.stop()
        wizard.leavePage()
    }

    /// Reads the Mac again. Calls that arrive while one is in flight are
    /// folded into a single read after it.
    func refresh() async {
        if detecting {
            detectAgain = true
            return
        }
        detecting = true
        repeat {
            detectAgain = false
            let next = await detect()
            perform(flow.receive(next))
        } while detectAgain
        detecting = false
    }

    private func wizardFinished() {
        perform(flow.wizardFinished())
    }

    private func perform(_ effect: OnboardingEffect?) {
        switch effect {
        case nil:
            break
        case let .run(steps):
            prepare.reset()
            Task { await runPrepare(steps) }
        case .openWizard:
            Task { await wizard.prepareFirstRun() }
        case .refreshDetection:
            Task { await refresh() }
        case .stop:
            leave()
            prepare.reset()
        }
    }

    private func runPrepare(_ steps: [MachinePlanStep]) async {
        await prepare.run(steps, inTerminal: false, label: "Setting up devmachine…")
        guard flow.plan == steps else { return }
        perform(flow.runFinished(succeeded: prepare.phase == .succeeded))
    }
}
