import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

/// What the Mac looks like, changed by the test as each step "runs".
private final class FakeMac: @unchecked Sendable {
    private let lock = NSLock()
    private var current: OnboardingDetection

    init(_ detection: OnboardingDetection) { current = detection }

    var detection: OnboardingDetection {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
}

/// Every command a run started, and how each ends, as the test decides.
@MainActor
private final class FakeProcesses {
    var ran: [[String]] = []
    var cliInstalls = 0
    var limaInstalls = 0
    var failing: [String: Int] = [:]
    var failureLine = "error: refused"
    var onRun: ([String]) -> Void = { _ in }
    var fetches = 0
    var waits: [TimeInterval] = []
    let catalog = WidgetCatalog(engine: "1.7", packagesRelease: "v54", widgets: [])
    var configDirectory: String?

    func fails(_ word: String, times: Int = 1) { failing[word] = times }

    private func status(for arguments: [String]) -> Int32 {
        guard let key = failing.keys.first(where: { arguments.joined(separator: " ").contains($0) }),
              let left = failing[key], left > 0
        else { return 0 }
        failing[key] = left - 1
        return 1
    }

    var hooks: MachineStepRunner.Hooks {
        MachineStepRunner.Hooks(
            executable: { "/Users/alice/.local/bin/devmachine" }, isReady: { _ in true }, type: { _, _ in },
            matchCount: { _, _ in 0 }, writeScript: { _, _ in "/tmp/x.sh" }, isAtPrompt: { _ in nil },
            runProcess: { arguments, _, output in
                self.ran.append(arguments)
                self.onRun(arguments)
                let status = self.status(for: arguments)
                output(status == 0 ? "ok" : self.failureLine)
                return status
            },
            beginTask: { _, _ in nil }, setTask: { _, _ in }, endTask: { _, _ in },
            installLima: { _, output in
                self.limaInstalls += 1
                output("Lima installed")
            },
            installCLI: { output in
                self.cliInstalls += 1
                let status = self.status(for: ["install-cli"])
                output(status == 0 ? "Installed devmachine" : "curl: (6) Could not resolve host: mydevmachine.sh")
                if status == 0 { self.onRun(["install-cli"]) }
                return status
            },
            fetchPackages: { output in
                self.fetches += 1
                guard self.status(for: ["fetch-packages"]) == 0 else {
                    output(self.failureLine)
                    throw DevmachineCLIError.commandFailed(self.failureLine)
                }
                output("Packages release v54: 0 widgets ready")
                return PackagesFetch(catalog: self.catalog, configDirectory: self.configDirectory)
            },
            sleep: { delay in await MainActor.run { self.waits.append(delay) } })
    }
}

@MainActor
final class OnboardingRunnerTests: XCTestCase {
    private let newCLI = MachineUnattendedAdd.minimumCLIVersion

    private func makeRunner(
        _ mac: FakeMac, _ processes: FakeProcesses, handOff: @escaping @MainActor (PackagesFetch) -> Void = { _ in }
    ) -> OnboardingRunner {
        let snapshot = MachinesSnapshot(hasConfiguration: false, machines: [], packages: [], cliVersion: newCLI)
        let wizard = AddMachineModel(
            machines: MachinesStore(read: { snapshot }, remove: { _ in }),
            runner: MachineStepRunner(hooks: processes.hooks, pollInterval: 1_000_000),
            findLima: { nil }, findBrew: { nil }, onAdded: {},
            skillAgents: { $0.filter { $0.harness == .claude } }, firstRun: true)
        return OnboardingRunner(
            detect: { mac.detection }, wizard: wizard,
            prepare: MachineStepRunner(hooks: processes.hooks, pollInterval: 1_000_000), handOff: handOff)
    }

    func testAFreshMacGetsTheCLIThenItsFirstMachineOnThisMacWithEveryLogShown() async throws {
        let mac = FakeMac(.empty)
        let processes = FakeProcesses()
        processes.onRun = { arguments in
            if arguments == ["install-cli"] {
                mac.detection = OnboardingDetection(
                    cliFound: true, adminMachine: nil, missingPackageMachines: [], cliVersion: self.newCLI)
            }
            if arguments.first == "machines" {
                var next = mac.detection
                next.adminMachine = "lab"
                mac.detection = next
            }
        }
        let runner = makeRunner(mac, processes)
        await runner.refresh()

        runner.start()
        try await waitFor { runner.flow.screen == .wizard }
        XCTAssertEqual(processes.cliInstalls, 1)
        XCTAssertTrue(runner.prepare.lines.contains("Installed devmachine"))

        try await waitFor { runner.wizard.wizard.firstRun && runner.wizard.wizard.unattended }
        runner.wizard.wizard.choose(.localVM)
        runner.wizard.wizard.draft.name = "lab"
        runner.wizard.wizard.next()
        runner.wizard.wizard.next()
        await runner.wizard.create()

        try await waitFor { runner.isAllSet }
        XCTAssertEqual(processes.limaInstalls, 1)
        XCTAssertEqual(processes.fetches, 1)
        XCTAssertEqual(processes.ran, [
            ["machines", "create-local", "lab", "--add"],
            ["packages", "add", "devmachine-app", "--machine", "lab", "--yes"],
            ["sync", "--machine", "lab", "--yes"],
            ["skills", "add", "--agent", "claude", "--yes"],
            ["run", "--machine", "lab", "--", "true"],
        ])
        XCTAssertEqual(runner.flow.plan.map(\.title), ["Download the packages release", "Check that lab answers"])
    }

    func testRetryResumesFromTheFailedStepAndSkipsWhatIsDone() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: true, adminMachine: "acme", missingPackageMachines: ["acme"], cliVersion: newCLI))
        let processes = FakeProcesses()
        processes.fails("sync")
        let runner = makeRunner(mac, processes)
        await runner.refresh()

        runner.start()
        try await waitFor { runner.prepare.phase == .failed(step: "sync --machine acme --yes") }
        XCTAssertEqual(processes.ran.count, 2)

        processes.onRun = { arguments in
            if arguments.first == "sync" {
                mac.detection = OnboardingDetection(
                    cliFound: true, adminMachine: "acme", missingPackageMachines: [], cliVersion: self.newCLI)
            }
        }
        runner.retry()
        try await waitFor { runner.isAllSet }
        XCTAssertEqual(processes.ran.map { $0[0] }, ["packages", "sync", "sync", "run"])
    }

    func testAFailedInstallSaysWhyAndBackForgetsTheRun() async throws {
        let mac = FakeMac(.empty)
        let processes = FakeProcesses()
        processes.fails("install-cli", times: 3)
        let runner = makeRunner(mac, processes)
        await runner.refresh()

        runner.start()
        try await waitFor { runner.prepare.phase == .failed(step: MachinePlanStep.installCLIID) }
        let help = SetupFailureHelp.help(for: .installCLI, lines: runner.prepare.lines)
        XCTAssertEqual(help.cause, .cliDownload)

        runner.back()
        XCTAssertEqual(runner.flow.screen, .start)
        XCTAssertEqual(runner.prepare.phase, .idle)
    }

    func testAFailedSkillsInstallBlocksTheFirstRunUntilRetryInstallsThem() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: true, adminMachine: nil, missingPackageMachines: [], cliVersion: newCLI))
        let processes = FakeProcesses()
        processes.fails("skills")
        processes.onRun = { arguments in
            if arguments.first == "machines" {
                var next = mac.detection
                next.adminMachine = "lab"
                mac.detection = next
            }
        }
        let runner = makeRunner(mac, processes)
        await runner.refresh()
        runner.start()
        try await waitFor { runner.flow.screen == .wizard && runner.wizard.wizard.unattended }
        runner.wizard.wizard.choose(.localVM)
        runner.wizard.wizard.draft.name = "lab"
        runner.wizard.wizard.next()
        runner.wizard.wizard.next()

        await runner.wizard.create()

        XCTAssertFalse(runner.wizard.onlySkillsFailed)
        XCTAssertEqual(runner.wizard.failedStep?.kind, .skills)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runner.flow.screen, .wizard)
        XCTAssertFalse(runner.isAllSet)

        await runner.wizard.retry()
        try await waitFor { runner.isAllSet }
        XCTAssertEqual(processes.ran.filter { $0[0] == "skills" }.count, 2)
        XCTAssertEqual(processes.ran.filter { $0[0] == "machines" }.count, 1)
    }

    func testANetworkFailureIsTriedThreeTimesThenFailsWithTheRealMessage() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: true, adminMachine: "acme", missingPackageMachines: [], cliVersion: newCLI))
        let processes = FakeProcesses()
        processes.failureLine = "fetching https://github.com/x: dial tcp: lookup github.com: no such host"
        processes.fails("fetch-packages", times: 5)
        let runner = makeRunner(mac, processes)
        await runner.refresh()

        try await waitFor { runner.prepare.phase == .failed(step: MachinePlanStep.fetchPackages.id) }
        XCTAssertEqual(processes.fetches, 3)
        XCTAssertEqual(processes.waits, [2, 5])
        XCTAssertEqual(runner.prepare.attemptLabel(of: .fetchPackages), "Attempt 3 of 3")
        XCTAssertEqual(runner.prepare.problem, "Tried 3 times. " + processes.failureLine)
        XCTAssertEqual(runner.prepare.lines.filter { $0 == processes.failureLine }.count, 3)
        XCTAssertFalse(runner.isAllSet)

        runner.retry()
        try await waitFor { runner.isAllSet }
        XCTAssertEqual(processes.fetches, 6)
    }

    func testANetworkFailureThatClearsOnTheSecondAttemptSucceeds() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: true, adminMachine: "acme", missingPackageMachines: [], cliVersion: newCLI))
        let processes = FakeProcesses()
        processes.failureLine = "ssh: connect to host 203.0.113.10 port 22: Operation timed out"
        processes.fails("run --machine", times: 1)
        let runner = makeRunner(mac, processes)
        await runner.refresh()

        try await waitFor { runner.isAllSet }
        XCTAssertEqual(processes.ran.filter { $0[0] == "run" }.count, 2)
        XCTAssertEqual(processes.waits, [2])
    }

    func testAFailureThatIsNotTheNetworksIsNotTriedAgain() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: true, adminMachine: "acme", missingPackageMachines: [], cliVersion: newCLI))
        let processes = FakeProcesses()
        processes.failureLine = "alice@203.0.113.10: Permission denied (publickey)."
        processes.fails("run --machine", times: 3)
        let runner = makeRunner(mac, processes)
        await runner.refresh()

        try await waitFor { runner.prepare.phase == .failed(step: MachinePlanStep.checkReady("acme").id) }
        XCTAssertEqual(processes.ran.filter { $0[0] == "run" }.count, 1)
        XCTAssertEqual(processes.waits, [])
        XCTAssertNil(runner.prepare.attemptLabel(of: .checkReady("acme")))
        XCTAssertFalse(runner.isAllSet)
    }

    func testAfterOnboardingHomeHoldsTheCatalogAndOpensItsBoardAtOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnboardingHandOff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogStore = WidgetCatalogStore(read: { throw DevmachineCLIError.commandFailed("not read in this test") })
        let home = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: catalogStore, configPath: { nil })
        let mac = FakeMac(OnboardingDetection(
            cliFound: true, adminMachine: "acme", missingPackageMachines: [], cliVersion: newCLI))
        let processes = FakeProcesses()
        processes.configDirectory = root.appendingPathComponent("config").path
        let runner = makeRunner(mac, processes, handOff: { home.handOff($0) })
        await runner.refresh()

        try await waitFor { runner.isAllSet }
        XCTAssertEqual(catalogStore.catalog, processes.catalog)
        XCTAssertEqual(catalogStore.state, .loaded)

        home.start()
        XCTAssertNotNil(home.store)
        XCTAssertEqual(catalogStore.state, .loaded)
        XCTAssertEqual(HomeCatalogNotice.of(catalog: catalogStore.catalog, state: catalogStore.state), .none)
    }

    func testAllSetNeedsEveryFinishingStepDoneNotOnlyACompleteScreen() {
        let ready = OnboardingDetection(
            cliFound: true, adminMachine: "acme", missingPackageMachines: [], cliVersion: newCLI)
        let steps = OnboardingPlan.finishSteps(for: ready)
        let runner = makeRunner(FakeMac(ready), FakeProcesses())
        runner.seedDemo(.demo(detection: ready, screen: .complete))

        for statuses: [MachineStepRunner.StepStatus] in [[.waiting, .waiting], [.done, .waiting], [.done, .failed],
                                                          [.running, .waiting], [.failed, .waiting]] {
            runner.prepare.seedDemo(
                statuses: Dictionary(uniqueKeysWithValues: zip(steps.map(\.id), statuses)), phase: .running)
            XCTAssertFalse(runner.isAllSet, "\(statuses)")
        }
        runner.prepare.seedDemo(
            statuses: Dictionary(uniqueKeysWithValues: steps.map { ($0.id, .done) }), phase: .succeeded)
        XCTAssertTrue(runner.isAllSet)

        var incomplete = ready
        incomplete.missingPackageMachines = ["acme"]
        runner.seedDemo(.demo(detection: incomplete, screen: .complete))
        XCTAssertFalse(runner.isAllSet)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
