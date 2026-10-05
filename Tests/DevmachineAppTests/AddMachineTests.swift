import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Stands in for the terminal: records what was typed, and "prints" the
/// marker each step's script would print, as the test decides.
@MainActor
private final class FakeTerminal {
    var typed: [String] = []
    var scripts: [String: String] = [:]
    var ready = true
    var executable: String? = "/opt/homebrew/bin/devmachine"
    /// The steps (by their arguments' first words) that end with an error.
    var failing: Set<String> = []
    /// Steps whose script never prints a marker: stopped, or still going.
    var silent: Set<String> = []
    /// What the pane's shell reports: true back at its prompt, nil unknown.
    var atPrompt: Bool?
    var promptChecks = 0
    var printed: [String] = []
    var tasks: [(String, Int)] = []
    var ended: [Bool] = []
    /// Background runs: each command's arguments and what it got on stdin.
    var processes: [(arguments: [String], input: Data?)] = []
    var processStatus: ([String]) -> Int32 = { _ in 0 }

    var hooks: MachineStepRunner.Hooks {
        MachineStepRunner.Hooks(
            executable: { self.executable },
            isReady: { _ in self.ready },
            type: { text, _ in self.typed.append(text) },
            matchCount: { term, _ in self.printed.filter { $0 == term }.count },
            writeScript: { script, nonce in
                let path = "/tmp/steps/\(nonce).sh"
                self.scripts[path] = script
                guard !self.silent.contains(where: { script.contains($0) }) else { return path }
                let fails = self.failing.contains { script.contains($0) }
                self.printed.append(fails ? TerminalStepMarker.fail(nonce: nonce) : TerminalStepMarker.ok(nonce: nonce))
                return path
            },
            isAtPrompt: { _ in
                self.promptChecks += 1
                return self.atPrompt
            },
            runProcess: { arguments, input, output in
                self.processes.append((arguments, input))
                let status = self.processStatus(arguments)
                output(status == 0 ? "ok: \(arguments[0])" : "Error: \(arguments[0]) refused")
                return status
            },
            beginTask: { label, total in
                self.tasks.append((label, total))
                return UUID()
            },
            setTask: { _, _ in },
            endTask: { _, succeeded in self.ended.append(succeeded) })
    }
}

@MainActor
final class MachineStepRunnerTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "D", count: 43)

    private func plan(packages: [String] = []) -> [MachinePlanStep] {
        var draft = MachineDraft()
        draft.name = "main"
        draft.address = "203.0.113.10"
        draft.fingerprint = fingerprint
        draft.keyFile = "~/.ssh/id_ed25519"
        draft.packages = packages
        return MachinePlan.steps(for: draft)
    }

    func testEveryStepRunsInOrderThroughAScriptTypedIntoTheTerminal() async {
        let terminal = FakeTerminal()
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan(packages: ["docker"])

        await runner.run(steps)

        XCTAssertEqual(runner.phase, .succeeded)
        XCTAssertEqual(terminal.typed.count, 3)
        XCTAssertTrue(terminal.typed.allSatisfy { $0.hasPrefix("sh /tmp/steps/") && $0.hasSuffix(".sh\r") })
        let scripts = terminal.typed.map { terminal.scripts[String($0.dropFirst(3).dropLast())] ?? "" }
        XCTAssertTrue(scripts[0].contains("/opt/homebrew/bin/devmachine machines add --name main"))
        XCTAssertTrue(scripts[1].contains("packages add docker --machine main --yes"))
        XCTAssertTrue(scripts[2].contains("sync --machine main --yes"))
        XCTAssertEqual(steps.map { runner.status(of: $0) }, [.done, .done, .done])
        XCTAssertEqual(terminal.tasks.first?.1, 3)
        XCTAssertEqual(terminal.ended, [true])
    }

    func testAFailedStepStopsTheRunAndSaysWhich() async {
        let terminal = FakeTerminal()
        terminal.failing = ["packages add docker"]
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan(packages: ["docker"])

        await runner.run(steps)

        XCTAssertEqual(runner.phase, .failed(step: steps[1].id))
        XCTAssertEqual(steps.map { runner.status(of: $0) }, [.done, .failed, .waiting])
        XCTAssertEqual(terminal.typed.count, 2)
        XCTAssertNotNil(runner.problem)
        XCTAssertEqual(terminal.ended, [false])
    }

    func testARetrySkipsWhatIsDoneAndRunsTheRest() async {
        let terminal = FakeTerminal()
        terminal.failing = ["packages add docker"]
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan(packages: ["docker"])
        await runner.run(steps)

        terminal.failing = []
        await runner.run(steps)

        XCTAssertEqual(runner.phase, .succeeded)
        XCTAssertEqual(terminal.typed.count, 4)
        XCTAssertFalse(terminal.scripts.values.filter { $0.contains("machines add") }.count > 1)
    }

    func testWithoutTheCLINothingIsTyped() async {
        let terminal = FakeTerminal()
        terminal.executable = nil
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)

        await runner.run(plan())

        XCTAssertEqual(terminal.typed, [])
        XCTAssertEqual(runner.problem, "The devmachine CLI was not found on this Mac.")
    }

    func testATerminalThatNeverStartsFailsInsteadOfWaitingForever() async {
        let terminal = FakeTerminal()
        terminal.ready = false
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000, readyTimeout: 3)

        await runner.run(plan())

        XCTAssertEqual(terminal.typed, [])
        XCTAssertEqual(runner.problem, "The terminal below did not start.")
    }

    func testAStepThatDiesWithoutAMarkerFailsOnceTheShellIsBackAtItsPrompt() async {
        let terminal = FakeTerminal()
        terminal.silent = ["machines add"]
        terminal.atPrompt = true
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan()

        await runner.run(steps)

        XCTAssertEqual(runner.phase, .failed(step: steps[0].id))
        XCTAssertEqual(runner.problem, MachineStepRunner.endedWithoutMarker)
        XCTAssertEqual(terminal.ended, [false])
    }

    func testAStepStillRunningIsNotMistakenForADeadOne() async {
        let terminal = FakeTerminal()
        terminal.silent = ["machines add"]
        terminal.atPrompt = false
        let runner = MachineStepRunner(
            hooks: terminal.hooks, pollInterval: 1_000_000, stepTimeout: 0.2)
        let steps = plan()

        await runner.run(steps)

        XCTAssertGreaterThan(terminal.promptChecks, 2)
        XCTAssertEqual(runner.phase, .failed(step: steps[0].id))
        XCTAssertEqual(runner.problem, MachineStepRunner.timedOut)
    }

    func testStoppingATerminalStepInterruptsItAndEndsTheRun() async throws {
        let terminal = FakeTerminal()
        terminal.silent = ["machines add"]
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan(packages: ["docker"])
        let run = Task { await runner.run(steps) }
        try await waitFor { runner.status(of: steps[0]) == .running && !terminal.typed.isEmpty }

        runner.stop()
        await run.value

        XCTAssertEqual(terminal.typed.last, "\u{03}")
        XCTAssertEqual(runner.phase, .failed(step: steps[0].id))
        XCTAssertEqual(runner.problem, MachineStepRunner.stopped)
        XCTAssertEqual(steps.map { runner.status(of: $0) }, [.failed, .waiting, .waiting])
        XCTAssertEqual(terminal.typed.count, 2, "nothing after the stopped step was typed")
        XCTAssertEqual(terminal.ended, [false])
    }

    func testResetForgetsTheRun() async {
        let terminal = FakeTerminal()
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan()
        await runner.run(steps)

        runner.reset()

        XCTAssertEqual(runner.phase, .idle)
        XCTAssertEqual(runner.status(of: steps[0]), .waiting)
    }
}

@MainActor
private func waitFor(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !condition() {
        if Date() > deadline { return XCTFail("condition never became true") }
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}

@MainActor
final class MachineStepRunnerBackgroundTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "K", count: 43)

    private func passwordPlan() -> [MachinePlanStep] {
        var draft = MachineDraft()
        draft.name = "backup"
        draft.address = "203.0.113.20"
        draft.fingerprint = fingerprint
        draft.login = .password
        draft.packages = ["docker"]
        return MachinePlan.steps(for: draft, unattended: true)
    }

    func testANewCLIRunsEveryStepWithoutATerminalAndThePasswordGoesOnlyToStdin() async {
        let terminal = FakeTerminal()
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = passwordPlan()

        await runner.run(steps, inTerminal: false, password: SecretText("hunter2"))

        XCTAssertEqual(runner.phase, .succeeded)
        XCTAssertTrue(runner.inBackground)
        XCTAssertEqual(terminal.typed, [])
        XCTAssertEqual(terminal.processes.map(\.arguments), steps.map(\.arguments))
        XCTAssertEqual(terminal.processes[0].input, Data("hunter2".utf8))
        XCTAssertNil(terminal.processes[1].input)
        XCTAssertFalse(terminal.processes.flatMap(\.arguments).contains { $0.contains("hunter2") })
        XCTAssertFalse(runner.lines.contains { $0.contains("hunter2") })
        XCTAssertEqual(runner.lines.first, "$ " + steps[0].displayLine)
        XCTAssertEqual(terminal.ended, [true])
    }

    func testAFailedCommandSaysTheCLIsOwnCauseAndARetryRunsItAgain() async {
        let terminal = FakeTerminal()
        terminal.processStatus = { $0.starts(with: ["machines", "add"]) ? 1 : 0 }
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = passwordPlan()

        await runner.run(steps, inTerminal: false, password: SecretText("wrong"))

        XCTAssertEqual(runner.phase, .failed(step: steps[0].id))
        XCTAssertEqual(runner.problem, "machines refused")
        XCTAssertEqual(steps.map { runner.status(of: $0) }, [.failed, .waiting, .waiting])

        terminal.processStatus = { _ in 0 }
        await runner.run(steps, inTerminal: false, password: SecretText("right"))

        XCTAssertEqual(runner.phase, .succeeded)
        XCTAssertEqual(terminal.processes.map(\.arguments), [steps[0].arguments] + steps.map(\.arguments))
        XCTAssertEqual(terminal.processes[1].input, Data("right".utf8))
    }

    func testStoppingABackgroundStepCancelsItsProcess() async throws {
        var hooks = FakeTerminal().hooks
        let started = Flag()
        let cancelled = Flag()
        hooks.runProcess = { _, _, _ in
            started.set()
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                cancelled.set()
                throw error
            }
            return 0
        }
        let runner = MachineStepRunner(hooks: hooks, pollInterval: 1_000_000)
        let steps = passwordPlan()
        let run = Task { await runner.run(steps, inTerminal: false, password: SecretText("hunter2")) }
        try await waitFor { started.value }

        runner.stop()
        await run.value

        XCTAssertTrue(cancelled.value)
        XCTAssertEqual(runner.phase, .failed(step: steps[0].id))
        XCTAssertEqual(runner.problem, MachineStepRunner.stopped)
    }

    func testACommandThatCannotStartFailsTheStep() async {
        struct NoCLI: Error, LocalizedError { var errorDescription: String? { "no CLI" } }
        var hooks = FakeTerminal().hooks
        hooks.runProcess = { _, _, _ in throw NoCLI() }
        let runner = MachineStepRunner(hooks: hooks, pollInterval: 1_000_000)
        let steps = passwordPlan()

        await runner.run(steps, inTerminal: false)

        XCTAssertEqual(runner.phase, .failed(step: steps[0].id))
        XCTAssertEqual(runner.problem, "no CLI")
    }
}

@MainActor
final class AddMachineModelTests: XCTestCase {
    private func store(_ snapshot: MachinesSnapshot) async -> MachinesStore {
        let store = MachinesStore(read: { snapshot }, remove: { _ in })
        await store.load()
        return store
    }

    func testTheWizardKnowsTheNamesTakenAndWhetherAConfigurationExists() async {
        let machines = await store(MachinesSnapshot(
            hasConfiguration: true,
            machines: [ConfiguredMachine(
                name: "main", hosts: ["203.0.113.10"], adminUser: "root", port: 22,
                workspaces: ["acme", "beta"], packages: [], isSelf: false)],
            packages: []))
        let model = AddMachineModel(
            machines: machines, runner: MachineStepRunner(hooks: FakeTerminal().hooks), findLima: { nil },
            onAdded: {})

        XCTAssertEqual(model.wizard.existingMachines, ["main"])
        XCTAssertEqual(model.wizard.existingWorkspaces, ["acme", "beta"])
        XCTAssertFalse(model.wizard.limaFound)
        XCTAssertTrue(model.wizard.draft.hasConfiguration)

        let empty = AddMachineModel(
            machines: await store(.none), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { "/opt/homebrew/bin/limactl" }, onAdded: {})
        XCTAssertFalse(empty.wizard.draft.hasConfiguration)
        XCTAssertTrue(empty.wizard.limaFound)
    }

    func testTheLocationFlagFollowsTheCLIVersionAndKnownLocationsAreOffered() async {
        func model(_ version: SemanticVersion) async -> AddMachineModel {
            AddMachineModel(
                machines: await store(MachinesSnapshot(
                    hasConfiguration: true,
                    machines: [ConfiguredMachine(
                        name: "main", hosts: ["203.0.113.10"], adminUser: "root", port: 22, workspaces: [],
                        packages: [], isSelf: false, reportedLocation: "hostinger")],
                    packages: [], cliVersion: version)),
                runner: MachineStepRunner(hooks: FakeTerminal().hooks), findLima: { nil }, onAdded: {})
        }
        let current = await model(MachineLocation.minimumCLIVersion)
        XCTAssertTrue(current.wizard.takesLocation)
        XCTAssertEqual(current.knownLocations, ["hostinger"])
        let older = await model(SemanticVersion(major: 0, minor: 7, patch: 29))
        XCTAssertFalse(older.wizard.takesLocation)
    }

    func testALimaMachineIsSizedFromThisMacOnlyOnACLIThatTakesTheSize() async {
        let limits = LocalMachineSizeLimits(cores: 8, memoryBytes: 16 << 30, freeDiskBytes: 200 << 30)
        func model(_ version: SemanticVersion) async -> AddMachineModel {
            AddMachineModel(
                machines: await store(MachinesSnapshot(
                    hasConfiguration: true, machines: [], packages: [], cliVersion: version)),
                runner: MachineStepRunner(hooks: FakeTerminal().hooks), findLima: { "/opt/homebrew/bin/limactl" },
                onAdded: {}, macLimits: { limits })
        }
        let sized = await model(LocalMachineSizing.minimumCLIVersion)
        XCTAssertEqual(sized.wizard.sizeLimits, limits)
        XCTAssertEqual(sized.wizard.draft.localSize, limits.defaultSize)

        sized.wizard.draft.localSize?.cpus = 6
        sized.refreshContext()
        XCTAssertEqual(sized.wizard.draft.localSize?.cpus, 6)

        let older = await model(MachineUnattendedAdd.minimumCLIVersion)
        XCTAssertNil(older.wizard.sizeLimits)
        XCTAssertNil(older.wizard.sizeToCreate)
    }

    func testCreatingRunsThePlanAndReloadsOnSuccess() async {
        let terminal = FakeTerminal()
        var added = 0
        let model = AddMachineModel(
            machines: await store(.none),
            runner: MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000),
            findLima: { "/opt/homebrew/bin/limactl" }, onAdded: { added += 1 })
        model.wizard.choose(.localVM)
        model.wizard.draft.name = "lab"
        model.wizard.next()
        model.wizard.next()

        await model.create()

        XCTAssertEqual(model.wizard.stage, .run)
        XCTAssertEqual(model.runner.phase, .succeeded)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(terminal.typed.count, 3)
    }

    func testOpeningThePageAfterASuccessStartsAFreshWizard() async {
        let model = AddMachineModel(
            machines: await store(.none),
            runner: MachineStepRunner(hooks: FakeTerminal().hooks, pollInterval: 1_000_000),
            findLima: { "/opt/homebrew/bin/limactl" }, onAdded: {})
        model.wizard.choose(.localVM)
        model.wizard.draft.name = "lab"
        model.wizard.next()
        model.wizard.next()
        await model.create()

        model.openPage()

        XCTAssertEqual(model.wizard.stage, .kind)
        XCTAssertEqual(model.wizard.draft.name, "")
    }

    private var newCLISnapshot: MachinesSnapshot {
        MachinesSnapshot(
            hasConfiguration: false, machines: [], packages: [], cliVersion: MachineUnattendedAdd.minimumCLIVersion)
    }

    func testANewCLIMakesTheWizardAddWithoutATerminal() async {
        let model = AddMachineModel(
            machines: await store(newCLISnapshot), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { nil }, onAdded: {})
        XCTAssertTrue(model.wizard.unattended)

        let old = AddMachineModel(
            machines: await store(.none), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { nil }, onAdded: {})
        XCTAssertFalse(old.wizard.unattended)
    }

    func testAPasswordServerIsAddedInTheBackgroundAndThePasswordIsForgottenAfter() async {
        let terminal = FakeTerminal()
        let fingerprint = "SHA256:" + String(repeating: "L", count: 43)
        var added = 0
        let model = AddMachineModel(
            machines: await store(newCLISnapshot),
            runner: MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000),
            findLima: { nil }, onAdded: { added += 1 },
            scanMachine: { address, port in
                MachineScan(address: address, port: Int(port) ?? 22, keyType: "ssh-ed25519",
                            fingerprint: fingerprint, verify: nil)
            })
        model.wizard.choose(.server)
        model.wizard.draft.name = "backup"
        model.wizard.draft.address = "203.0.113.20"
        model.wizard.draft.login = .password
        model.wizard.draft.password = SecretText("hunter2")
        await model.scan()
        XCTAssertFalse(model.wizard.canAdvance)
        model.wizard.draft.scanConfirmed = true
        model.wizard.next()
        model.wizard.next()

        await model.create()

        XCTAssertEqual(model.runner.phase, .succeeded)
        XCTAssertEqual(terminal.typed, [])
        XCTAssertEqual(terminal.processes.first?.arguments, [
            "machines", "add", "--name", "backup", "--address", "203.0.113.20", "--fingerprint", fingerprint,
            "--password-stdin", "--yes",
        ])
        XCTAssertEqual(terminal.processes.first?.input, Data("hunter2".utf8))
        XCTAssertEqual(model.wizard.draft.password.value, "")
        XCTAssertEqual(added, 1)
    }

    func testAScanThatFailsSaysWhyAndTrustsNothing() async {
        struct Refused: Error, LocalizedError { var errorDescription: String? { "connection refused" } }
        let model = AddMachineModel(
            machines: await store(newCLISnapshot), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { nil }, onAdded: {}, scanMachine: { _, _ in throw Refused() })
        model.wizard.choose(.server)
        model.wizard.draft.address = "203.0.113.20"

        await model.scan()

        XCTAssertEqual(model.scanError, "connection refused")
        XCTAssertNil(model.wizard.draft.scan)
        XCTAssertFalse(model.scanning)
    }

    func testASingleAgentKeyIsChosenForThePerson() async {
        let key = AgentKey(fingerprint: "SHA256:" + String(repeating: "M", count: 43), comment: "alice", type: "ED25519")
        let model = AddMachineModel(
            machines: await store(newCLISnapshot), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { nil }, onAdded: {}, listAgentKeys: { [key] })

        await model.loadAgentKeys()

        XCTAssertEqual(model.agentKeys, [key])
        XCTAssertEqual(model.wizard.draft.agentKey, key.fingerprint)
    }

    func testAnAgentThatDoesNotAnswerSaysSo() async {
        struct NoAgent: Error, LocalizedError { var errorDescription: String? { "no agent" } }
        let model = AddMachineModel(
            machines: await store(newCLISnapshot), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { nil }, onAdded: {}, listAgentKeys: { throw NoAgent() })

        await model.loadAgentKeys()

        XCTAssertEqual(model.agentKeys, [])
        XCTAssertEqual(model.agentKeysError, "no agent")
    }

    private func passwordModel(
        _ terminal: FakeTerminal, machines: MachinesStore? = nil
    ) async -> AddMachineModel {
        let fingerprint = "SHA256:" + String(repeating: "L", count: 43)
        let resolved: MachinesStore
        if let machines { resolved = machines } else { resolved = await store(newCLISnapshot) }
        let model = AddMachineModel(
            machines: resolved,
            runner: MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000),
            findLima: { nil }, onAdded: {})
        model.wizard.choose(.server)
        model.wizard.draft.name = "backup"
        model.wizard.draft.address = "203.0.113.20"
        model.wizard.draft.login = .password
        model.wizard.draft.password = SecretText("hunter2")
        model.wizard.draft.fingerprint = fingerprint
        return model
    }

    func testAFailedRunForgetsThePasswordAndItsRetryAsksForItAgain() async {
        let terminal = FakeTerminal()
        terminal.processStatus = { $0.starts(with: ["machines", "add"]) ? 1 : 0 }
        let model = await passwordModel(terminal)
        model.wizard.next()
        model.wizard.next()

        await model.create()

        XCTAssertEqual(model.runner.phase, .failed(step: model.wizard.plan[0].id))
        XCTAssertEqual(model.wizard.draft.password.value, "")
        XCTAssertFalse(model.canRetry)

        await model.retry()

        XCTAssertEqual(model.wizard.stage, .details)
        XCTAssertEqual(model.wizard.draft.name, "backup")
        XCTAssertEqual(terminal.processes.count, 1, "nothing ran again without a password")
    }

    func testEditAnswersAfterAFailureKeepsThemAndASecondCreateRunsTheFixedPlan() async {
        let terminal = FakeTerminal()
        terminal.processStatus = { $0.contains("203.0.113.20") ? 1 : 0 }
        let model = await passwordModel(terminal)
        model.wizard.next()
        model.wizard.next()
        await model.create()

        model.editAnswers()
        XCTAssertEqual(model.wizard.stage, .details)
        model.wizard.draft.address = "203.0.113.21"
        model.wizard.draft.password = SecretText("hunter2")
        model.wizard.next()
        model.wizard.next()
        await model.create()

        XCTAssertEqual(model.runner.phase, .succeeded)
        XCTAssertEqual(terminal.processes.filter { $0.arguments.contains("203.0.113.21") }.count, 1)
    }

    func testClosingAfterAFailureReopensOnTheAnswers() async {
        let terminal = FakeTerminal()
        terminal.processStatus = { _ in 1 }
        let model = await passwordModel(terminal)
        model.wizard.next()
        model.wizard.next()
        await model.create()

        model.close()
        model.openPage()

        XCTAssertEqual(model.wizard.stage, .details)
        XCTAssertEqual(model.wizard.draft.address, "203.0.113.20")
    }

    func testLeavingThePageForgetsThePassword() async {
        let model = await passwordModel(FakeTerminal())

        model.leavePage()

        XCTAssertEqual(model.wizard.draft.password.value, "")
        XCTAssertEqual(model.wizard.draft.name, "backup")
    }

    func testReadingTheContextAgainNeverCarriesThePassword() async {
        let model = await passwordModel(FakeTerminal())

        model.refreshContext()

        XCTAssertEqual(model.wizard.draft.password.value, "")
        XCTAssertEqual(model.wizard.draft.address, "203.0.113.20")
    }

    func testANewerCLIFoundWhileReviewingSendsThePersonBackToWhatItNeeds() async {
        let snapshot = Snapshots()
        snapshot.value = .none
        let machines = MachinesStore(read: { snapshot.value }, remove: { _ in })
        await machines.load()
        let model = AddMachineModel(
            machines: machines, runner: MachineStepRunner(hooks: FakeTerminal().hooks), findLima: { nil },
            onAdded: {})
        model.wizard.choose(.server)
        model.wizard.draft.name = "backup"
        model.wizard.draft.address = "203.0.113.20"
        model.wizard.draft.login = .password
        model.wizard.next()
        model.wizard.next()
        XCTAssertEqual(model.wizard.stage, .review)

        snapshot.value = newCLISnapshot
        await machines.load()
        model.openPage()

        XCTAssertTrue(model.wizard.unattended)
        XCTAssertEqual(model.wizard.stage, .details)
        XCTAssertTrue(model.wizard.problems.contains { $0.field == .password })
    }

    func testTheMachineThisRunAlreadyAddedDoesNotBlockItsOwnName() async {
        let terminal = FakeTerminal()
        terminal.processStatus = { $0.starts(with: ["sync"]) ? 1 : 0 }
        let snapshot = Snapshots()
        snapshot.value = newCLISnapshot
        let machines = MachinesStore(read: { snapshot.value }, remove: { _ in })
        await machines.load()
        let model = await passwordModel(terminal, machines: machines)
        model.wizard.next()
        model.wizard.next()
        await model.create()
        XCTAssertEqual(model.runner.phase, .failed(step: model.wizard.plan.last!.id))

        snapshot.value = MachinesSnapshot(
            hasConfiguration: true,
            machines: [ConfiguredMachine(
                name: "backup", hosts: ["203.0.113.20"], adminUser: "root", port: 22, workspaces: [],
                packages: [], isSelf: false)],
            packages: [], cliVersion: MachineUnattendedAdd.minimumCLIVersion)
        await machines.load()
        model.editAnswers()

        XCTAssertFalse(model.wizard.problems.contains { $0.field == .name })
    }

    func testOpeningThePageKeepsAnswersNotRunYet() async {
        let model = AddMachineModel(
            machines: await store(.none), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { nil }, onAdded: {})
        model.wizard.choose(.server)
        model.wizard.draft.name = "main"

        model.openPage()

        XCTAssertEqual(model.wizard.stage, .details)
        XCTAssertEqual(model.wizard.draft.name, "main")
    }
}

@MainActor
final class MachinesStoreTests: XCTestCase {
    func testNothingIsOfferedBeforeTheFirstRead() {
        let store = MachinesStore(read: { .none }, remove: { _ in })
        XCTAssertNil(store.remoteMachineNames)
    }

    func testThisMacIsNotAMachineToOfferOneFor() async {
        let store = MachinesStore(
            read: {
                MachinesSnapshot(
                    hasConfiguration: true,
                    machines: [ConfiguredMachine(
                        name: "laptop", hosts: [], adminUser: "", port: 0, workspaces: [], packages: [],
                        isSelf: true)],
                    packages: [])
            },
            remove: { _ in })
        await store.load()
        XCTAssertEqual(store.remoteMachineNames, [])
        XCTAssertTrue(AddMachinePrompt.shows(remoteMachines: store.remoteMachineNames))
    }

    func testAFailedReadSaysSoAndOffersNoButton() async {
        struct Broken: Error, LocalizedError { var errorDescription: String? { "config.yml: bad indent" } }
        let store = MachinesStore(read: { throw Broken() }, remove: { _ in })
        await store.load()
        guard case .failed = store.phase else { return XCTFail("expected a failure, got \(store.phase)") }
        XCTAssertNil(store.remoteMachineNames)
    }

    func testRemovingAMachineGoesThroughTheCLIThenReadsAgain() async {
        let removed = RemovedNames()
        let store = MachinesStore(read: { .none }, remove: { removed.append($0) })
        await store.removeMachine("staging")
        XCTAssertEqual(removed.names, ["staging"])
        XCTAssertNil(store.removalError)
        XCTAssertEqual(store.remoteMachineNames, [])
    }

    func testALoadAskedForDuringAnotherRunsAgainAfterIt() async throws {
        let reads = Counter()
        let gate = Gate()
        let store = MachinesStore(read: {
            reads.increment()
            await gate.wait()
            return .none
        }, remove: { _ in })
        let first = Task { await store.load() }
        try await waitFor { reads.value == 1 }

        await store.load()
        await store.load()
        await gate.open()
        await first.value

        XCTAssertEqual(reads.value, 2)
    }

    func testARefusedRemovalShowsTheCLIsWords() async {
        struct Refused: Error, LocalizedError {
            var errorDescription: String? { "machine staging still has workspaces: umbrella" }
        }
        let store = MachinesStore(read: { .none }, remove: { _ in throw Refused() })
        await store.removeMachine("staging")
        XCTAssertEqual(store.removalError?.details, "machine staging still has workspaces: umbrella")
    }
}

private final class Snapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = MachinesSnapshot.none
    var value: MachinesSnapshot {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    func increment() { lock.withLock { stored += 1 } }
}

/// Holds every read until opened; opened for good, so nothing stays held.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}

private final class RemovedNames: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var names: [String] { lock.withLock { stored } }
    func append(_ name: String) { lock.withLock { stored.append(name) } }
}

/// Answers `config path`, `packages list` and `machines list` like the CLI.
private struct ConfigRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        switch Array(args.dropFirst(2)) {
        case ["config", "path"]:
            return #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#
        case ["packages", "list"]:
            return #"""
            {"packages":[
              {"name":"essentials","scope":"machine","source":"release","summary":"Most machines want it.","installed_on":["machine main"]},
              {"name":"docker","scope":"machine","source":"release","summary":"Docker.","installed_on":[]},
              {"name":"zsh","scope":"workspace","source":"release","summary":"A shell.","installed_on":["workspace acme"]}
            ]}
            """#
        case ["machines", "list"]:
            return #"[{"name":"main","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":["acme"]}]"#
        default:
            throw DevmachineCLIError.commandFailed("unexpected \(args)")
        }
    }
}

final class MachinesReaderTests: XCTestCase {
    private let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: ConfigRunner())

    func testNoConfigurationMeansNoMachineAndNoCall() throws {
        let snapshot = try MachinesReader.read(cli: cli, fileExists: { _ in false })
        XCTAssertEqual(snapshot, .none)
    }

    func testEachMachineCarriesThePackagesThatNameIt() throws {
        let snapshot = try MachinesReader.read(
            cli: cli, fileExists: { $0 == "/Users/alice/.config/devmachine/config.yml" })
        XCTAssertTrue(snapshot.hasConfiguration)
        XCTAssertEqual(snapshot.machines.map(\.name), ["main"])
        XCTAssertEqual(snapshot.machines.first?.packages, ["essentials"])
        XCTAssertEqual(snapshot.machines.first?.workspaces, ["acme"])
        XCTAssertEqual(
            MachinePackageCatalog.cards(from: snapshot.packages.map(\.info)).map(\.name), ["essentials", "docker"])
    }
}

/// A CLI that adds without a terminal: reports its version, each
/// machine's own packages, and packages with platforms and needs. Records
/// every call.
private final class NewCLIRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var calls: [[String]] { lock.withLock { recorded } }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.withLock { recorded.append(args) }
        switch args {
        case ["version"]:
            return "devmachine 0.7.27\n"
        case ["--format", "json", "config", "path"]:
            return #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#
        case ["--format", "json", "packages", "list"]:
            return #"""
            {"release":"v17","packages":[
              {"name":"essentials","scope":"machine","source":"release","summary":"Most machines want it.",
               "platforms":["linux"],"needs":["base","git"],"installed_on":[]},
              {"name":"homebrew-apps","scope":"machine","source":"release","summary":"Casks.",
               "platforms":["macos"],"needs":[],"installed_on":[]}
            ]}
            """#
        case ["--format", "json", "machines", "list"]:
            return #"[{"name":"main","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":[],"packages":["essentials","docker"]}]"#
        default:
            throw DevmachineCLIError.commandFailed("unexpected \(args)")
        }
    }
}

final class MachinesReaderNewCLITests: XCTestCase {
    func testWithNoConfigurationANewCLIStillListsTheLatestReleaseForTheFirstMachine() throws {
        let runner = NewCLIRunner()
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)

        let snapshot = try MachinesReader.read(cli: cli, fileExists: { _ in false })

        XCTAssertFalse(snapshot.hasConfiguration)
        XCTAssertEqual(snapshot.machines, [])
        XCTAssertTrue(snapshot.addsWithoutTerminal)
        XCTAssertEqual(snapshot.packages.first?.needs, ["base", "git"])
        XCTAssertEqual(
            MachinePackageCatalog.cards(from: snapshot.packages.map(\.info)).map(\.name), ["essentials"])
        XCTAssertFalse(runner.calls.contains(["--format", "json", "machines", "list"]))
    }

    func testEachMachinesPackagesComeFromItsOwnList() throws {
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: NewCLIRunner())

        let snapshot = try MachinesReader.read(
            cli: cli, fileExists: { $0 == "/Users/alice/.config/devmachine/config.yml" })

        XCTAssertEqual(snapshot.machines.first?.packages, ["essentials", "docker"])
        XCTAssertEqual(snapshot.cliVersion, SemanticVersion(major: 0, minor: 7, patch: 27))
    }
}

/// Answers `machines scan` and `ssh-add -l` like the real tools.
private struct ScanRunner: CommandRunner {
    let fingerprint: String
    var agentExit: Int32 = 0

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        if executable == AgentKeyList.executable {
            XCTAssertEqual(args, ["-l", "-E", "sha256"])
            XCTAssertNotNil(environment?["SSH_AUTH_SOCK"])
            switch agentExit {
            case 0: return ("256 \(fingerprint) alice@example.com (ED25519)\n", "", 0)
            case 1: return ("The agent has no identities.\n", "", 1)
            default: return ("", "Could not open a connection to your authentication agent.\n", 2)
            }
        }
        XCTAssertEqual(args, ["--format", "json", "machines", "scan", "--address", "203.0.113.20", "--port", "2222"])
        return (#"{"address":"203.0.113.20","port":2222,"key_type":"ssh-ed25519","fingerprint":"\#(fingerprint)"}"#, "", 0)
    }
}

final class DevmachineCLIMachineTrustTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "N", count: 43)

    private func cli(agentExit: Int32 = 0) -> DevmachineCLI {
        DevmachineCLI(
            executable: "/opt/homebrew/bin/devmachine",
            runner: ScanRunner(fingerprint: fingerprint, agentExit: agentExit),
            customSocket: "/Users/alice/agent.sock", socketFileExists: { _ in true }, processEnvironment: [:])
    }

    func testAScanIsReadForTheAddressAndPortAsked() throws {
        let scan = try cli().scanMachine(address: "203.0.113.20", port: "2222")
        XCTAssertEqual(scan.fingerprint, fingerprint)
        XCTAssertNil(scan.verify)
        XCTAssertEqual(scan.target, "203.0.113.20:2222")
    }

    func testTheAgentsKeysAreListedThroughTheAppsSocket() throws {
        XCTAssertEqual(try cli().agentKeys().map(\.fingerprint), [fingerprint])
        XCTAssertEqual(try cli(agentExit: 1).agentKeys(), [])
        XCTAssertThrowsError(try cli(agentExit: 2).agentKeys())
    }
}
