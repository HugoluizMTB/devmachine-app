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

    func testOnboardingRunsNoStepAndNoAgent() async {
        let panes = RecordingPanes()
        let agent = DetectedAgent(kind: .claude, executablePath: "/Users/alice/.local/bin/claude")
        let runner = OnboardingRunner(
            home: "/Users/alice", launcher: panes,
            detect: { _ in
                OnboardingDetection(cliFound: false, adminMachine: nil, missingPackageMachines: [], agents: [agent])
            })
        await runner.refresh()

        runner.start()
        XCTAssertEqual(runner.flow.phase, .failed(.installCLI, .demo))

        runner.back()
        runner.startAgent(.claude)
        XCTAssertEqual(runner.flow.phase, .agentStopped(.claude))
        XCTAssertTrue(panes.launched.isEmpty)
    }

    func testOnboardingReadsNoRealCLIInDemoMode() async {
        let runner = OnboardingRunner(home: "/Users/alice", launcher: RecordingPanes())

        await runner.refresh()

        XCTAssertEqual(runner.flow.detection, DemoSetupFlow.freshMac)
    }
}

@MainActor
private final class RecordingPanes: OnboardingPaneLaunching {
    var launched: [PaneProgram] = []

    func launch(_ program: PaneProgram, in kind: TerminalKind, onExit: @escaping @MainActor (Int32?) -> Void) {
        launched.append(program)
    }

    func close(_ kind: TerminalKind) {}
}
