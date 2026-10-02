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
    cliFound: Bool = true, adminMachine: String? = nil,
    missingPackageMachines: [String] = [], agents: [DetectedAgent] = []
) -> OnboardingDetection {
    OnboardingDetection(
        cliFound: cliFound, adminMachine: adminMachine,
        missingPackageMachines: missingPackageMachines, agents: agents)
}

// MARK: - OnboardingPlan.missingSteps

final class OnboardingPlanMissingStepsTests: XCTestCase {
    func testEverythingMissingListsInstallAndSetupOnly() {
        let steps = OnboardingPlan.missingSteps(for: .empty)
        XCTAssertEqual(steps, [.installCLI, .runSetup])
    }

    func testCLIFoundButNoMachineSkipsTheInstallStep() {
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

}

// MARK: - OnboardingPlan.commands

final class OnboardingPlanCommandsTests: XCTestCase {
    func testAFreshMacInstallsTheBinaryWithoutHomebrewOrXcode() {
        let commands = OnboardingPlan.commands(for: .empty)
        XCTAssertEqual(commands.map(\.id), [.installCLI, .runSetup])
        XCTAssertEqual(commands[0].command, "curl -fsSL https://mydevmachine.sh/install.sh | DEVMACHINE_NO_BREW=1 sh")
        XCTAssertEqual(commands[1].command, #"PATH="$HOME/.local/bin:$PATH" devmachine setup"#)
    }

    func testCommandsForAMissingPackageUseTheMachineName() {
        let commands = OnboardingPlan.commands(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme"]))
        XCTAssertEqual(commands.map(\.command), [
            #"PATH="$HOME/.local/bin:$PATH" devmachine packages add devmachine-app --machine acme"#,
            #"PATH="$HOME/.local/bin:$PATH" devmachine sync --machine acme"#,
        ])
    }

    func testCommandsForSeveralMissingMachinesListEachOnesPair() {
        let commands = OnboardingPlan.commands(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme", "beta"]))
        XCTAssertEqual(commands.map(\.id), [
            .addPackage(machine: "acme"), .sync(machine: "acme"),
            .addPackage(machine: "beta"), .sync(machine: "beta"),
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
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) },
            agents: { [] })
        XCTAssertTrue(result.cliFound)
        XCTAssertEqual(result.adminMachine, "acme")
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertTrue(result.isComplete)
    }

    func testMissingCLIReportsNothingElseDetected() {
        let result = OnboardingDetector.detect(
            cli: { throw DevmachineCLIError.executableNotFound(["/fake"]) },
            agents: { [] })
        XCTAssertFalse(result.cliFound)
        XCTAssertNil(result.adminMachine)
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertFalse(result.isComplete)
    }

    func testCLIFoundButNoMachineConfiguredLeavesThePackageUnchecked() {
        let runner = ScriptedRunner(byCommand: ["machines": ("[]", "", 0)])
        let result = OnboardingDetector.detect(
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
    func testTheTypedLineNeverContainsItsOwnMarkers() {
        let typed = OnboardingMarker.wrap("brew install foo", nonce: "k3x9")
        XCTAssertFalse(typed.contains(OnboardingMarker.ok(nonce: "k3x9")))
        XCTAssertFalse(typed.contains(OnboardingMarker.fail(nonce: "k3x9")))
    }

    func testTheShellPrintsOkOrFailForThatRunOnly() throws {
        for (command, marker) in [
            ("true", OnboardingMarker.ok(nonce: "a1")),
            ("false", OnboardingMarker.fail(nonce: "a1")),
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", OnboardingMarker.wrap(command, nonce: "a1")]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTAssertEqual(out, marker + "\n", command)
        }
    }

    func testOutcomeComesFromThisRunsMarkerAlone() {
        XCTAssertNil(OnboardingMarker.outcome(okSeen: false, failSeen: false))
        XCTAssertEqual(OnboardingMarker.outcome(okSeen: true, failSeen: false), .done)
        XCTAssertEqual(
            OnboardingMarker.outcome(okSeen: false, failSeen: true),
            .failed("This step exited with an error. See the terminal above."))
    }

    func testEveryRunGetsItsOwnNonce() {
        XCTAssertNotEqual(OnboardingMarker.newNonce(), OnboardingMarker.newNonce())
    }
}

@MainActor
final class OnboardingRunnerTests: XCTestCase {
    private final class Screen: SessionCommandSending, @unchecked Sendable {
        var text = ""
        var printOnRun: ((String) -> String)?
        func send(_ command: String, into target: CommandTarget) throws {
            text += command + "\n"
            if let printOnRun { text += printOnRun(command) }
        }
    }

    private func runner(_ screen: Screen) -> OnboardingRunner {
        OnboardingRunner(sender: screen, matchCounter: { term, _ in
            screen.text.components(separatedBy: term).count - 1
        }, pollInterval: 5_000_000)
    }

    func testAStepIsNotDoneJustBecauseItsLineWasTyped() async throws {
        let screen = Screen()
        let runner = runner(screen)
        runner.run(steps: [(.installCLI, "curl x | sh")])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.status(for: .installCLI), .running)
    }

    func testAFailedStepStopsTheRunAndCanBeTriedAgain() async throws {
        let screen = Screen()
        var exitCode = "FAIL"
        screen.printOnRun = { command in
            guard let nonce = OnboardingMarker.nonce(inTyped: command) else { return "" }
            return "__DM_\(nonce)_\(exitCode)__\n"
        }
        let runner = runner(screen)
        let steps: [(id: OnboardingStepID, command: String)] = [(.installCLI, "curl x | sh"), (.runSetup, "devmachine setup")]
        runner.run(steps: steps)
        try await waitFor { runner.status(for: .installCLI) != .running && runner.status(for: .installCLI) != .waiting }
        XCTAssertEqual(runner.status(for: .installCLI), .failed("This step exited with an error. See the terminal above."))
        XCTAssertEqual(runner.status(for: .runSetup), .waiting)
        XCTAssertFalse(screen.text.contains("devmachine setup"), "nothing runs after a failure")

        exitCode = "OK"
        runner.retry(step: .installCLI, remaining: steps)
        try await waitFor { runner.status(for: .runSetup) == .done }
        XCTAssertEqual(runner.status(for: .installCLI), .done)
    }

    func testResetForgetsEveryStep() async throws {
        let screen = Screen()
        screen.printOnRun = { command in
            OnboardingMarker.nonce(inTyped: command).map { "__DM_\($0)_FAIL__\n" } ?? ""
        }
        let runner = runner(screen)
        runner.run(steps: [(.installCLI, "curl x | sh")])
        try await waitFor { runner.status(for: .installCLI) != .running && runner.status(for: .installCLI) != .waiting }
        runner.reset()
        XCTAssertEqual(runner.status(for: .installCLI), .waiting)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

final class AgentHelpPromptTests: XCTestCase {
    func testTheHelpPromptNamesTheStepAndTheCommandToRunAgain() {
        let line = AgentPrompt.helpCommandLine(for: .claude, step: .installCLI, command: "curl x | sh")
        XCTAssertTrue(line.hasPrefix("claude \""))
        XCTAssertTrue(line.contains("Install the devmachine CLI"))
        XCTAssertTrue(line.contains("curl x | sh"))
        XCTAssertTrue(line.contains("Run it again"))
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

}
