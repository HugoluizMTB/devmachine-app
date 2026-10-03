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
    var onRun: ([String]) -> Void = { _ in }

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
                output(status == 0 ? "ok" : "error: \(arguments[0]) refused")
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
            })
    }
}

@MainActor
final class OnboardingRunnerTests: XCTestCase {
    private let newCLI = MachineUnattendedAdd.minimumCLIVersion

    private func makeRunner(_ mac: FakeMac, _ processes: FakeProcesses) -> OnboardingRunner {
        let snapshot = MachinesSnapshot(hasConfiguration: false, machines: [], packages: [], cliVersion: newCLI)
        let wizard = AddMachineModel(
            machines: MachinesStore(read: { snapshot }, remove: { _ in }),
            runner: MachineStepRunner(hooks: processes.hooks, pollInterval: 1_000_000),
            findLima: { nil }, findBrew: { nil }, onAdded: {},
            skillAgents: { $0.filter { $0.harness == .claude } }, firstRun: true)
        return OnboardingRunner(
            detect: { mac.detection }, wizard: wizard,
            prepare: MachineStepRunner(hooks: processes.hooks, pollInterval: 1_000_000))
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

        XCTAssertEqual(processes.limaInstalls, 1)
        XCTAssertEqual(processes.ran, [
            ["machines", "create-local", "lab", "--add"],
            ["packages", "add", "devmachine-app", "--machine", "lab", "--yes"],
            ["sync", "--machine", "lab", "--yes"],
            ["skills", "add", "--agent", "claude", "--yes"],
        ])
        try await waitFor { runner.flow.screen == .complete }
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
        try await waitFor { runner.flow.screen == .complete }
        XCTAssertEqual(processes.ran.map { $0[0] }, ["packages", "sync", "sync"])
    }

    func testAFailedInstallSaysWhyAndBackForgetsTheRun() async throws {
        let mac = FakeMac(.empty)
        let processes = FakeProcesses()
        processes.fails("install-cli")
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

    func testAFailedSkillsInstallIsAWarningAndTheSetupStillCompletes() async throws {
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

        XCTAssertTrue(runner.wizard.onlySkillsFailed)
        try await waitFor { runner.flow.screen == .complete }

        await runner.wizard.retry()
        XCTAssertEqual(processes.ran.filter { $0[0] == "skills" }.count, 2)
        XCTAssertEqual(processes.ran.filter { $0[0] == "machines" }.count, 1)
        XCTAssertFalse(runner.wizard.onlySkillsFailed)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
