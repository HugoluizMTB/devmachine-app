import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private let claude = DetectedAgent(kind: .claude, executablePath: "/Users/alice/.local/bin/claude")

private func detection(
    cliFound: Bool = true, adminMachine: String? = nil,
    missingPackageMachines: [String] = [], agents: [DetectedAgent] = []
) -> OnboardingDetection {
    OnboardingDetection(
        cliFound: cliFound, adminMachine: adminMachine,
        missingPackageMachines: missingPackageMachines, agents: agents)
}

private let freshMac = detection(cliFound: false, agents: [claude])
private let cliOnly = detection(cliFound: true, agents: [claude])
private let serverWithoutPackage = detection(adminMachine: "acme", missingPackageMachines: ["acme"])
private let ready = detection(adminMachine: "acme")

final class OnboardingFlowTests: XCTestCase {
    func testANewCLIConnectsTheServerWithoutATerminal() {
        var newCLI = cliOnly
        newCLI.cliVersion = MachineUnattendedAdd.minimumCLIVersion
        var flow = OnboardingFlow()
        _ = flow.receive(newCLI)

        XCTAssertEqual(flow.start(), .connectServer)
        XCTAssertEqual(flow.phase, .running(.runSetup))
        XCTAssertEqual(flow.stepExited(.runSetup, exitCode: 0), .refreshDetection)
        XCTAssertEqual(
            flow.receive(detection(adminMachine: "acme", missingPackageMachines: ["acme"])),
            .runStep(.addPackage(machine: "acme"), command: OnboardingPlan.addPackageCommand(machine: "acme")))
    }

    func testAnOlderCLIStillRunsSetupInATerminal() {
        var oldCLI = cliOnly
        oldCLI.cliVersion = SemanticVersion(major: 0, minor: 7, patch: 26)
        var flow = OnboardingFlow()
        _ = flow.receive(oldCLI)

        XCTAssertEqual(flow.start(), .runStep(.runSetup, command: OnboardingPlan.setupCommand))
    }

    func testNothingCanStartBeforeTheFirstDetection() {
        var flow = OnboardingFlow()
        XCTAssertFalse(flow.hasDetected)
        XCTAssertNil(flow.start())
        XCTAssertEqual(flow.phase, .start)
    }

    func testAFreshMacRunsEveryStepToCompletion() {
        var flow = OnboardingFlow()
        XCTAssertNil(flow.receive(freshMac))

        XCTAssertEqual(flow.start(), .runStep(.installCLI, command: OnboardingPlan.installCLICommand))
        XCTAssertEqual(flow.phase, .running(.installCLI))

        XCTAssertEqual(flow.stepExited(.installCLI, exitCode: 0), .refreshDetection)
        XCTAssertEqual(flow.phase, .checking(.installCLI))
        XCTAssertEqual(flow.receive(cliOnly), .runStep(.runSetup, command: OnboardingPlan.setupCommand))

        XCTAssertEqual(flow.stepExited(.runSetup, exitCode: 0), .refreshDetection)
        XCTAssertEqual(
            flow.receive(serverWithoutPackage),
            .runStep(.addPackage(machine: "acme"), command: OnboardingPlan.addPackageCommand(machine: "acme")))

        XCTAssertEqual(flow.stepExited(.addPackage(machine: "acme"), exitCode: 0), .refreshDetection)
        XCTAssertEqual(
            flow.receive(serverWithoutPackage),
            .runStep(.sync(machine: "acme"), command: OnboardingPlan.syncCommand(machine: "acme")))

        XCTAssertEqual(flow.stepExited(.sync(machine: "acme"), exitCode: 0), .refreshDetection)
        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.phase, .complete)
        XCTAssertEqual(
            flow.steps, [.installCLI, .runSetup, .addPackage(machine: "acme"), .sync(machine: "acme")])
        XCTAssertTrue(flow.steps.allSatisfy { flow.status(of: $0) == .done })
    }

    func testSyncStillRunsWhenThePackageReadsAsInstalledRightAfterItIsAdded() {
        var flow = OnboardingFlow()
        _ = flow.receive(serverWithoutPackage)
        _ = flow.start()
        _ = flow.stepExited(.addPackage(machine: "acme"), exitCode: 0)

        XCTAssertEqual(
            flow.receive(ready),
            .runStep(.sync(machine: "acme"), command: OnboardingPlan.syncCommand(machine: "acme")))
        XCTAssertNotEqual(flow.phase, .complete)
    }

    func testANonZeroExitFailsTheStepAndRunsNothingAfterIt() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()

        XCTAssertNil(flow.stepExited(.installCLI, exitCode: 1))
        XCTAssertEqual(flow.phase, .failed(.installCLI, .exited(1)))
        XCTAssertEqual(flow.status(of: .installCLI), .failed(OnboardingFailure.exited(1).message(for: .installCLI)))
        XCTAssertEqual(flow.status(of: .runSetup), .waiting)
    }

    func testAStepStoppedBySignalFailsToo() {
        var flow = OnboardingFlow()
        _ = flow.receive(cliOnly)
        _ = flow.start()

        XCTAssertNil(flow.stepExited(.runSetup, exitCode: nil))
        XCTAssertEqual(flow.phase, .failed(.runSetup, .exited(nil)))
    }

    func testAFailedStepCanBeTriedAgain() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()
        _ = flow.stepExited(.installCLI, exitCode: 1)

        XCTAssertEqual(flow.retry(), .runStep(.installCLI, command: OnboardingPlan.installCLICommand))
        XCTAssertEqual(flow.phase, .running(.installCLI))
    }

    func testASuccessfulExitThatChangedNothingIsAFailureNotALoop() {
        var flow = OnboardingFlow()
        _ = flow.receive(cliOnly)
        _ = flow.start()
        _ = flow.stepExited(.runSetup, exitCode: 0)

        XCTAssertNil(flow.receive(cliOnly))
        XCTAssertEqual(flow.phase, .failed(.runSetup, .unresolved))
        XCTAssertEqual(flow.status(of: .runSetup), .failed(OnboardingFailure.unresolved.message(for: .runSetup)))
        XCTAssertEqual(flow.retry(), .runStep(.runSetup, command: OnboardingPlan.setupCommand))
    }

    func testAnInstallTheAppStillCannotSeeFailsInsteadOfRunningSetup() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()
        _ = flow.stepExited(.installCLI, exitCode: 0)

        XCTAssertNil(flow.receive(freshMac))
        XCTAssertEqual(flow.phase, .failed(.installCLI, .unresolved))
    }

    func testASyncThatLeavesThePackageMissingFails() {
        var flow = OnboardingFlow()
        _ = flow.receive(serverWithoutPackage)
        _ = flow.start()
        _ = flow.stepExited(.addPackage(machine: "acme"), exitCode: 0)
        _ = flow.receive(serverWithoutPackage)
        _ = flow.stepExited(.sync(machine: "acme"), exitCode: 0)

        XCTAssertNil(flow.receive(serverWithoutPackage))
        XCTAssertEqual(flow.phase, .failed(.sync(machine: "acme"), .unresolved))
        XCTAssertEqual(
            flow.retry(),
            .runStep(.sync(machine: "acme"), command: OnboardingPlan.syncCommand(machine: "acme")))
    }

    func testEveryFailureMessageSaysWhatHappened() {
        let steps: [OnboardingStepID] = [.installCLI, .runSetup, .addPackage(machine: "acme"), .sync(machine: "acme")]
        for step in steps {
            for failure in [OnboardingFailure.exited(2), .exited(nil), .unresolved] {
                XCTAssertFalse(failure.message(for: step).isEmpty)
            }
        }
        XCTAssertTrue(OnboardingFailure.exited(2).message(for: .installCLI).contains("2"))
    }

    func testBackStopsThePaneAndForgetsTheRun() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()
        _ = flow.stepExited(.installCLI, exitCode: 0)
        _ = flow.receive(cliOnly)

        XCTAssertEqual(flow.back(), .stopPane)
        XCTAssertEqual(flow.phase, .start)
        XCTAssertEqual(flow.status(of: .installCLI), .waiting)
    }

    func testAnExitFromAStepThatIsNotRunningIsIgnored() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()
        _ = flow.back()

        XCTAssertNil(flow.stepExited(.installCLI, exitCode: 1))
        XCTAssertEqual(flow.phase, .start)
    }

    func testAMacAlreadySetUpIsCompleteAtOnce() {
        var flow = OnboardingFlow()
        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.phase, .complete)
    }

    func testCompleteNeverInterruptsAStepStillRunning() {
        var flow = OnboardingFlow()
        _ = flow.receive(cliOnly)
        _ = flow.start()

        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.phase, .running(.runSetup))
    }

    // MARK: - Agent

    func testTheAgentStartsWithTheSetupPrompt() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)

        XCTAssertEqual(flow.startAgent(.claude), .launchAgent(.claude, prompt: AgentPrompt.setup))
        XCTAssertEqual(flow.phase, .agentRunning(.claude))
    }

    func testTheAgentFinishingTheSetupCompletesWhileItIsStillOpen() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.startAgent(.claude)

        XCTAssertNil(flow.receive(cliOnly))
        XCTAssertEqual(flow.phase, .agentRunning(.claude))
        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.phase, .complete)
    }

    func testAnAgentThatQuitsEarlyOffersTheWayOn() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.startAgent(.claude)

        XCTAssertEqual(flow.agentExited(), .refreshDetection)
        XCTAssertEqual(flow.phase, .agentStopped(.claude))
        XCTAssertNil(flow.receive(cliOnly))
        XCTAssertEqual(flow.phase, .agentStopped(.claude))
        XCTAssertEqual(flow.start(), .runStep(.runSetup, command: OnboardingPlan.setupCommand))
    }

    func testAnAgentThatQuitsAfterFinishingCompletes() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.startAgent(.claude)
        _ = flow.agentExited()

        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.phase, .complete)
    }

    func testAskingTheAgentAboutAFailedStepHandsItTheStepAndCommand() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()
        _ = flow.stepExited(.installCLI, exitCode: 6)

        let effect = flow.askAgent(.claude)
        XCTAssertEqual(
            effect,
            .launchAgent(.claude, prompt: AgentPrompt.help(step: .installCLI, command: OnboardingPlan.installCLICommand)))
        XCTAssertEqual(flow.phase, .agentRunning(.claude))
    }

    func testAskingTheAgentWithoutAFailureDoesNothing() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        XCTAssertNil(flow.askAgent(.claude))
    }
}

final class OnboardingProgramsTests: XCTestCase {
    func testAStepRunsInALoginShellAndFailsWhenAnyPartOfAPipeFails() {
        let program = OnboardingPrograms.step("curl -fsSL https://example.com/x | sh")
        XCTAssertEqual(program.executable, "/bin/zsh")
        XCTAssertEqual(program.args, ["-l", "-i", "-c", "setopt pipefail; curl -fsSL https://example.com/x | sh"])
        XCTAssertTrue(program.environment.contains("DISABLE_AUTO_UPDATE=true"))
    }

    func testTheAgentIsTheProgramAndThePromptIsOneArgumentWithNoQuoting() {
        let prompt = #"Say "hi" and `whoami` and $HOME"#
        let program = OnboardingPrograms.agent(claude, prompt: prompt)
        XCTAssertEqual(program.executable, "/bin/zsh")
        XCTAssertEqual(Array(program.args.suffix(2)), ["/Users/alice/.local/bin/claude", prompt])
        XCTAssertTrue(program.args.contains { $0.contains(#"exec "$1" "$2""#) })
    }

    func testThePipefailPrefixReallyFailsAPipe() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", OnboardingPrograms.pipefail + "false | true"]
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
    }
}

final class AgentPromptTests: XCTestCase {
    func testTheSetupPromptPointsAtTheGuideAndTheAppPackage() {
        XCTAssertTrue(AgentPrompt.setup.contains("https://mydevmachine.sh/agent-setup.md"))
        XCTAssertTrue(AgentPrompt.setup.contains("devmachine-app"))
        XCTAssertTrue(AgentPrompt.setup.contains("sync"))
    }

    func testTheHelpPromptNamesTheStepAndTheCommandToRunAgain() {
        let text = AgentPrompt.help(step: .installCLI, command: "curl x | sh")
        XCTAssertTrue(text.contains("Install the devmachine CLI"))
        XCTAssertTrue(text.contains("curl x | sh"))
        XCTAssertTrue(text.contains("Run it again"))
    }
}
