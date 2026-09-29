import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    private let byCommand: [String: (stdout: String, stderr: String, exitCode: Int32)]

    init(byCommand: [String: (stdout: String, stderr: String, exitCode: Int32)]) {
        self.byCommand = byCommand
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(args)
        lock.unlock()
        let key = args.contains("machines") ? "machines" : (args.contains("packages") ? "list" : (args.last ?? ""))
        return byCommand[key] ?? ("", "not stubbed: \(args)", 1)
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

private func detection(
    homebrewFound: Bool = true, cliFound: Bool = true, adminMachine: String? = nil,
    missingPackageMachines: [String] = [], agents: [DetectedAgent] = []
) -> OnboardingDetection {
    OnboardingDetection(
        homebrewFound: homebrewFound, cliFound: cliFound, adminMachine: adminMachine,
        missingPackageMachines: missingPackageMachines, agents: agents)
}

// MARK: - OnboardingPlan.missingSteps

final class OnboardingPlanMissingStepsTests: XCTestCase {
    func testEverythingMissingListsTrustTapInstallAndSetupOnly() {
        // No machine is known yet, so there is nothing to add the package to.
        let steps = OnboardingPlan.missingSteps(for: .empty)
        XCTAssertEqual(steps, [.trustTap, .installCLI, .runSetup])
    }

    func testCLIFoundButNoMachineSkipsTheTapAndInstallSteps() {
        let steps = OnboardingPlan.missingSteps(for: detection(cliFound: true, adminMachine: nil))
        XCTAssertEqual(steps, [.runSetup])
    }

    func testOneMissingMachineAddsOnePairOfSteps() {
        let steps = OnboardingPlan.missingSteps(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme"]))
        XCTAssertEqual(steps, [.addPackage(machine: "acme"), .sync(machine: "acme")])
    }

    func testSeveralMissingMachinesEachGetTheirOwnPairInOrder() {
        let steps = OnboardingPlan.missingSteps(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme", "beta"]))
        XCTAssertEqual(steps, [
            .addPackage(machine: "acme"), .sync(machine: "acme"),
            .addPackage(machine: "beta"), .sync(machine: "beta"),
        ])
    }

    func testNothingMissingListsNoSteps() {
        let steps = OnboardingPlan.missingSteps(for: detection(adminMachine: "acme", missingPackageMachines: []))
        XCTAssertEqual(steps, [])
    }

    func testAMachineHintFillsInThePackageStepsBeforeDetectionKnowsAboutIt() {
        // The package-only gate already knows which machine is missing the
        // package before onboarding's own detection has run once.
        let steps = OnboardingPlan.missingSteps(for: .empty, machine: "acme")
        XCTAssertTrue(steps.contains(.addPackage(machine: "acme")))
        XCTAssertTrue(steps.contains(.sync(machine: "acme")))
    }

    func testHomebrewMissingIsNeverAStepOfItsOwn() {
        // Homebrew is shown as a banner, never run by the app, so it never
        // appears in the runnable step list even when everything else is missing.
        let steps = OnboardingPlan.missingSteps(for: detection(homebrewFound: false, cliFound: false))
        XCTAssertFalse(steps.contains(where: { $0.title.lowercased().contains("homebrew") }))
    }
}

// MARK: - OnboardingPlan.commands

final class OnboardingPlanCommandsTests: XCTestCase {
    func testCommandsForAFreshMachineListTapInstallAndSetup() {
        let commands = OnboardingPlan.commands(for: .empty)
        XCTAssertEqual(commands.map(\.id), [.trustTap, .installCLI, .runSetup])
        XCTAssertEqual(commands[0].command, "brew trust --formula mydevmachine/tap/devmachine")
        XCTAssertEqual(commands[1].command, "brew install mydevmachine/tap/devmachine")
        XCTAssertEqual(commands[2].command, "devmachine setup")
    }

    func testCommandsForAMissingPackageUseTheMachineName() {
        let commands = OnboardingPlan.commands(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme"]))
        XCTAssertEqual(commands.map(\.command), [
            "devmachine packages add devmachine-app --machine acme",
            "devmachine sync --machine acme",
        ])
    }

    func testCommandsForSeveralMissingMachinesListEachOnesPair() {
        let commands = OnboardingPlan.commands(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme", "beta"]))
        XCTAssertEqual(commands.map(\.command), [
            "devmachine packages add devmachine-app --machine acme",
            "devmachine sync --machine acme",
            "devmachine packages add devmachine-app --machine beta",
            "devmachine sync --machine beta",
        ])
    }
}

// MARK: - OnboardingDetector

final class OnboardingDetectorTests: XCTestCase {
    func testEverythingReadyReportsComplete() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":[]}]"#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let result = OnboardingDetector.detect(
            homebrewPaths: ["/fake/brew"], exists: { $0 == "/fake/brew" },
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) },
            agents: { [] })

        XCTAssertTrue(result.homebrewFound)
        XCTAssertTrue(result.cliFound)
        XCTAssertEqual(result.adminMachine, "acme")
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertTrue(result.isComplete)
    }

    func testMissingCLIReportsNothingElseDetected() {
        let result = OnboardingDetector.detect(
            homebrewPaths: ["/fake/brew"], exists: { _ in false },
            cli: { throw DevmachineCLIError.executableNotFound(["/fake"]) },
            agents: { [] })

        XCTAssertFalse(result.homebrewFound)
        XCTAssertFalse(result.cliFound)
        XCTAssertNil(result.adminMachine)
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertFalse(result.isComplete)
    }

    func testCLIFoundButNoMachineConfiguredLeavesThePackageUnchecked() {
        let runner = ScriptedRunner(byCommand: ["machines": ("[]", "", 0)])
        let result = OnboardingDetector.detect(
            homebrewPaths: ["/fake/brew"], exists: { $0 == "/fake/brew" },
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) },
            agents: { [] })

        XCTAssertTrue(result.cliFound)
        XCTAssertNil(result.adminMachine)
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertFalse(runner.calls.contains { $0.contains("packages") })
    }

    func testSeveralMachinesReportsOnlyTheOnesMissingThePackage() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"""
                [{"name":"acme","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":[]},
                 {"name":"beta","hosts":["203.0.113.20"],"admin_user":"root","port":22,"workspaces":[]}]
                """#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let result = OnboardingDetector.detect(
            homebrewPaths: ["/fake/brew"], exists: { $0 == "/fake/brew" },
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) },
            agents: { [] })

        XCTAssertEqual(result.missingPackageMachines, ["beta"])
        XCTAssertFalse(result.isComplete)
    }

    func testAFailedPackagesReadFailsOpenWithNothingMissing() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":[]}]"#, "", 0),
            "list": ("", "connection refused", 1),
        ])
        let result = OnboardingDetector.detect(
            homebrewPaths: ["/fake/brew"], exists: { $0 == "/fake/brew" },
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) },
            agents: { [] })

        XCTAssertEqual(result.missingPackageMachines, [])
        // Failing open still leaves the machine detected, so `isComplete`
        // reads true rather than stuck behind a flaky `packages` read.
        XCTAssertTrue(result.isComplete)
    }
}

// MARK: - AgentDetector

final class AgentDetectorTests: XCTestCase {
    func testAKnownPathIsFoundWithoutTouchingTheShell() {
        let runner = ScriptedRunner(byCommand: [:])
        let agents = AgentDetector.detect(
            kinds: [.claude], runner: runner, shell: "/bin/zsh",
            exists: { $0 == "/opt/homebrew/bin/claude" })

        XCTAssertEqual(agents, [DetectedAgent(kind: .claude, executablePath: "/opt/homebrew/bin/claude")])
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testFallsBackToTheLoginShellWhenNoKnownPathExists() {
        let runner = ScriptedRunner(byCommand: ["command -v codex": ("/Users/alice/.local/bin/codex\n", "", 0)])
        let agents = AgentDetector.detect(
            kinds: [.codex], runner: runner, shell: "/bin/zsh",
            exists: { $0 == "/Users/alice/.local/bin/codex" })

        XCTAssertEqual(agents, [DetectedAgent(kind: .codex, executablePath: "/Users/alice/.local/bin/codex")])
    }

    func testNeitherAKnownPathNorTheShellFindsItLeavesItUndetected() {
        let runner = ScriptedRunner(byCommand: [:])
        let agents = AgentDetector.detect(kinds: [.claude], runner: runner, shell: "/bin/zsh", exists: { _ in false })
        XCTAssertTrue(agents.isEmpty)
    }

    func testAnEmptyShellAnswerIsNotTreatedAsFound() {
        let runner = ScriptedRunner(byCommand: ["command -v claude": ("\n", "", 0)])
        let agents = AgentDetector.detect(kinds: [.claude], runner: runner, shell: "/bin/zsh", exists: { _ in false })
        XCTAssertTrue(agents.isEmpty)
    }
}

// MARK: - AgentPrompt

final class AgentPromptTests: XCTestCase {
    func testClaudeCommandLineQuotesThePromptAsOneArgument() {
        let line = AgentPrompt.commandLine(for: .claude)
        XCTAssertTrue(line.hasPrefix("claude \""))
        XCTAssertTrue(line.hasSuffix("\""))
        XCTAssertTrue(line.contains("mydevmachine.sh/agent-setup.md"))
    }

    func testCodexCommandLineUsesItsOwnExecutableName() {
        let line = AgentPrompt.commandLine(for: .codex)
        XCTAssertTrue(line.hasPrefix("codex \""))
    }

    func testEmbeddedQuotesAreEscapedSoTheShellSeesOneArgument() {
        let quoted = AgentPrompt.shellQuote(#"say "hi" and `whoami` and $HOME"#)
        XCTAssertEqual(quoted, #""say \"hi\" and \`whoami\` and \$HOME""#)
    }
}

// MARK: - OnboardingMarker

final class OnboardingMarkerTests: XCTestCase {
    func testWrapAppendsAnIfElseThatEchoesOkOrFail() {
        let wrapped = OnboardingMarker.wrap("brew install foo")
        XCTAssertEqual(wrapped, "brew install foo; if [ $? -eq 0 ]; then echo __DM_STEP_OK__; else echo __DM_STEP_FAIL__; fi")
    }

    func testOutcomeIsNilUntilAFreshMarkerAppears() {
        XCTAssertNil(OnboardingMarker.outcome(okCount: 0, failCount: 0, stepsFinishedBefore: 0))
        XCTAssertNil(OnboardingMarker.outcome(okCount: 1, failCount: 0, stepsFinishedBefore: 1))
    }

    func testOutcomeIsDoneWhenTheFreshMarkerIsOk() {
        XCTAssertEqual(OnboardingMarker.outcome(okCount: 1, failCount: 0, stepsFinishedBefore: 0), .done)
        XCTAssertEqual(OnboardingMarker.outcome(okCount: 4, failCount: 1, stepsFinishedBefore: 3), .done)
    }

    func testOutcomeIsFailedWhenTheFreshMarkerIsFail() {
        XCTAssertEqual(
            OnboardingMarker.outcome(okCount: 0, failCount: 1, stepsFinishedBefore: 0),
            .failed("This step exited with an error. See the terminal above."))
        XCTAssertEqual(
            OnboardingMarker.outcome(okCount: 2, failCount: 2, stepsFinishedBefore: 3),
            .failed("This step exited with an error. See the terminal above."))
    }

    func testAnOlderStepsMarkersDoNotCountAsThisStepFinishing() {
        // Two steps already finished ok; nothing new has appeared yet for the third.
        XCTAssertNil(OnboardingMarker.outcome(okCount: 2, failCount: 0, stepsFinishedBefore: 2))
    }
}

// MARK: - OnboardingDetection.isComplete (success detection)

final class OnboardingDetectionCompleteTests: XCTestCase {
    func testCompleteOnlyWhenCLIMachineAndEveryMachinesPackageAllHold() {
        XCTAssertFalse(OnboardingDetection.empty.isComplete)

        var result = detection(cliFound: true, adminMachine: nil, missingPackageMachines: [])
        XCTAssertFalse(result.isComplete)

        result.adminMachine = "acme"
        XCTAssertTrue(result.isComplete)

        result.missingPackageMachines = ["acme"]
        XCTAssertFalse(result.isComplete)

        result.missingPackageMachines = []
        XCTAssertTrue(result.isComplete)
    }

    func testHomebrewMissingDoesNotBlockCompletionOnceEverythingElseIsThere() {
        // Homebrew is only needed to install the CLI; once the CLI, machine
        // and package are all in place it no longer matters.
        let result = detection(homebrewFound: false, cliFound: true, adminMachine: "acme", missingPackageMachines: [])
        XCTAssertTrue(result.isComplete)
    }
}
