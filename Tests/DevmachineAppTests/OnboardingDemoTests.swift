import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class OnboardingDemoTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("DEVMACHINE_DEMO", "1", 1)
    }

    override func tearDown() {
        unsetenv("DEVMACHINE_DEMO")
        super.tearDown()
    }

    func testOnboardingRunsNoStep() async throws {
        let runner = OnboardingRunner()
        await runner.refresh()

        runner.start()
        let deadline = Date().addingTimeInterval(2)
        while runner.prepare.phase == .idle || runner.prepare.phase == .running, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(runner.prepare.phase, .failed(step: MachinePlanStep.installCLIID))
        XCTAssertEqual(runner.prepare.problem, MachineStepRunner.demoRefusal)
    }

    func testOnboardingReadsNoRealCLIInDemoMode() async {
        let runner = OnboardingRunner()

        await runner.refresh()

        XCTAssertEqual(runner.flow.detection, DemoSetupFlow.freshMac)
    }

    func testTheFirstRunWizardReadsNoServerAndNoAgentInDemoMode() async {
        let wizard = AddMachineModel.forOnboarding()
        await wizard.prepareFirstRun()
        XCTAssertTrue(wizard.wizard.firstRun)
        XCTAssertEqual(wizard.wizard.draft.skillAgents.map(\.id), ["claude", "codex"])
        XCTAssertEqual(wizard.wizard.draft.packages, ["docker"])
    }

    func testTheFirstRunOffersTheSkillsToEveryHarnessTheAppKnows() async {
        let wizard = AddMachineModel.forOnboarding()
        await wizard.prepareFirstRun()
        XCTAssertEqual(wizard.wizard.skillAgentOptions.map(\.harness), HarnessRegistry.builtIn.adapters.map(\.id))
        XCTAssertEqual(wizard.wizard.skillAgentOptions.map(\.id),
                       ["claude", "codex", "pi", "antigravity", "opencode", "kimi", "cline"])
    }
}
