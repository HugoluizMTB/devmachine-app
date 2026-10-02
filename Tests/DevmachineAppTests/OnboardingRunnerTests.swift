import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
private final class FakePanes: OnboardingPaneLaunching {
    struct Launch {
        let program: PaneProgram
        let kind: TerminalKind
        let onExit: @MainActor (Int32?) -> Void
    }

    var launches: [Launch] = []
    var closed: [TerminalKind] = []

    func launch(_ program: PaneProgram, in kind: TerminalKind, onExit: @escaping @MainActor (Int32?) -> Void) {
        launches.append(Launch(program: program, kind: kind, onExit: onExit))
    }

    func close(_ kind: TerminalKind) {
        closed.append(kind)
    }

    func exitLast(_ code: Int32?) {
        launches.last?.onExit(code)
    }
}

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

private final class AgentQuestions: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [[DetectedAgent]?] = []
    var values: [[DetectedAgent]?] { lock.withLock { stored } }
    func record(_ value: [DetectedAgent]?) { lock.withLock { stored.append(value) } }
}

private let serverKey = "SHA256:" + String(repeating: "N", count: 43)

private final class ProcessLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [(arguments: [String], input: Data?)] = []
    var calls: [(arguments: [String], input: Data?)] { lock.withLock { stored } }
    func append(_ arguments: [String], _ input: Data?) { lock.withLock { stored.append((arguments, input)) } }
}

private let claude = DetectedAgent(kind: .claude, executablePath: "/Users/alice/.local/bin/claude")

@MainActor
final class OnboardingRunnerTests: XCTestCase {
    private func makeRunner(_ mac: FakeMac, panes: FakePanes, poll: UInt64 = 5_000_000) -> OnboardingRunner {
        OnboardingRunner(
            home: "/Users/alice", launcher: panes,
            detect: { _ in mac.detection }, agentPollInterval: poll)
    }

    func testOneButtonCarriesAFreshMacToTheEnd() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: false, adminMachine: nil, missingPackageMachines: [], agents: [claude]))
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes)
        await runner.refresh()

        runner.start()
        XCTAssertEqual(panes.launches.count, 1)
        XCTAssertTrue(panes.launches[0].program.args.contains { $0.contains("install.sh") })
        XCTAssertEqual(runner.paneKind, panes.launches[0].kind)

        mac.detection.cliFound = true
        panes.exitLast(0)
        try await waitFor { panes.launches.count == 2 }
        XCTAssertTrue(panes.launches[1].program.args.contains { $0.hasSuffix("devmachine setup") })
        XCTAssertNotEqual(panes.launches[0].kind, panes.launches[1].kind, "each step gets a fresh pane")
        XCTAssertTrue(panes.closed.contains(panes.launches[0].kind))

        mac.detection.adminMachine = "acme"
        mac.detection.missingPackageMachines = ["acme"]
        panes.exitLast(0)
        try await waitFor { panes.launches.count == 3 }
        XCTAssertTrue(panes.launches[2].program.args.contains { $0.contains("packages add devmachine-app --machine acme") })

        panes.exitLast(0)
        try await waitFor { panes.launches.count == 4 }
        XCTAssertTrue(panes.launches[3].program.args.contains { $0.contains("sync --machine acme") })

        mac.detection.missingPackageMachines = []
        panes.exitLast(0)
        try await waitFor { runner.flow.phase == .complete }
        XCTAssertEqual(panes.launches.count, 4)
    }

    func testAFailedStepWaitsForTheChoiceThenTriesAgain() async throws {
        let mac = FakeMac(.empty)
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes)
        await runner.refresh()
        runner.start()

        panes.exitLast(1)
        XCTAssertEqual(runner.flow.phase, .failed(.installCLI, .exited(1)))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(panes.launches.count, 1, "nothing runs after a failure on its own")

        runner.retry()
        XCTAssertEqual(panes.launches.count, 2)
        XCTAssertEqual(runner.flow.phase, .running(.installCLI))
    }

    func testAnExitFromAPaneThatWasReplacedIsIgnored() async throws {
        let mac = FakeMac(.empty)
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes)
        await runner.refresh()
        runner.start()
        let first = panes.launches[0]
        runner.back()
        runner.start()

        first.onExit(1)
        XCTAssertEqual(runner.flow.phase, .running(.installCLI))
    }

    func testBackClosesThePane() async {
        let mac = FakeMac(.empty)
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes)
        await runner.refresh()
        runner.start()
        let kind = panes.launches[0].kind

        runner.back()
        XCTAssertTrue(panes.closed.contains(kind))
        XCTAssertNil(runner.paneKind)
        XCTAssertEqual(runner.flow.phase, .start)
    }

    func testTheAgentIsLaunchedAsThePanesProgramAndItsProgressIsWatched() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: false, adminMachine: nil, missingPackageMachines: [], agents: [claude]))
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes)
        await runner.refresh()

        runner.startAgent(.claude)
        XCTAssertEqual(panes.launches.count, 1)
        XCTAssertEqual(panes.launches[0].program.args.suffix(2), [claude.executablePath, AgentPrompt.setup])
        XCTAssertEqual(runner.flow.phase, .agentRunning(.claude))

        mac.detection = OnboardingDetection(
            cliFound: true, adminMachine: "acme", missingPackageMachines: [], agents: [claude])
        try await waitFor { runner.flow.phase == .complete }
    }

    func testOnlyTheFirstReadLooksForAgentsAndLaterOnesReuseThem() async throws {
        let asked = AgentQuestions()
        let runner = OnboardingRunner(
            home: "/Users/alice", launcher: FakePanes(),
            detect: { known in
                asked.record(known)
                return OnboardingDetection(
                    cliFound: false, adminMachine: nil, missingPackageMachines: [], agents: known ?? [claude])
            },
            agentPollInterval: 5_000_000)
        await runner.refresh()

        runner.startAgent(.claude)
        try await waitFor { asked.values.count >= 3 }
        runner.leave()

        XCTAssertEqual(asked.values.first, .some(nil))
        XCTAssertTrue(asked.values.dropFirst().allSatisfy { $0 == [claude] })
    }

    func testAnAgentThatQuitsIsReportedAndTheButtonsComeBack() async throws {
        let mac = FakeMac(OnboardingDetection(
            cliFound: false, adminMachine: nil, missingPackageMachines: [], agents: [claude]))
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes, poll: 5_000_000_000)
        await runner.refresh()
        runner.startAgent(.claude)

        panes.exitLast(0)
        XCTAssertEqual(runner.flow.phase, .agentStopped(.claude))
    }

    func testAnUnknownAgentIsNotLaunched() async {
        let mac = FakeMac(.empty)
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes)
        await runner.refresh()

        runner.startAgent(.codex)
        XCTAssertTrue(panes.launches.isEmpty)
        XCTAssertEqual(runner.flow.phase, .start)
    }

    func testLeavingClosesWhateverIsStillRunning() async {
        let mac = FakeMac(.empty)
        let panes = FakePanes()
        let runner = makeRunner(mac, panes: panes)
        await runner.refresh()
        runner.start()
        let kind = panes.launches[0].kind

        runner.leave()
        XCTAssertTrue(panes.closed.contains(kind))
    }

    private func connectModel(
        version: SemanticVersion? = MachineUnattendedAdd.minimumCLIVersion,
        status: @escaping @MainActor ([String]) -> Int32 = { _ in 0 }, ran: ProcessLog = ProcessLog()
    ) -> AddMachineModel {
        let snapshot = MachinesSnapshot(hasConfiguration: false, machines: [], packages: [], cliVersion: version)
        let hooks = MachineStepRunner.Hooks(
            executable: { "/opt/homebrew/bin/devmachine" }, isReady: { _ in true }, type: { _, _ in },
            matchCount: { _, _ in 0 }, writeScript: { _, _ in "/tmp/x.sh" }, isAtPrompt: { _ in nil },
            runProcess: { arguments, input, _ in
                ran.append(arguments, input)
                return status(arguments)
            },
            beginTask: { _, _ in nil }, setTask: { _, _ in }, endTask: { _, _ in })
        return AddMachineModel(
            machines: MachinesStore(read: { snapshot }, remove: { _ in }),
            runner: MachineStepRunner(hooks: hooks, pollInterval: 1_000_000),
            findLima: { nil }, onAdded: {},
            scanMachine: { address, port in
                MachineScan(address: address, port: Int(port) ?? 22, keyType: "ssh-ed25519",
                            fingerprint: serverKey, verify: nil)
            },
            connectOnly: true)
    }

    private func fill(_ model: AddMachineModel) async {
        model.wizard.draft.name = "acme"
        model.wizard.draft.address = "203.0.113.10"
        model.wizard.draft.login = .password
        model.wizard.draft.password = SecretText("hunter2")
        model.wizard.draft.domain = "example.com"
        await model.scan()
        model.wizard.draft.scanConfirmed = true
    }

    func testANewCLIConnectsTheServerInTheWizardThenAddsThePackageInAPane() async throws {
        var start = OnboardingDetection(cliFound: true, adminMachine: nil, missingPackageMachines: [], agents: [])
        start.cliVersion = MachineUnattendedAdd.minimumCLIVersion
        let mac = FakeMac(start)
        let panes = FakePanes()
        let ran = ProcessLog()
        let connect = connectModel(ran: ran)
        let runner = OnboardingRunner(
            home: "/Users/alice", launcher: panes, detect: { _ in mac.detection }, connect: connect)
        await runner.refresh()

        runner.start()
        try await waitFor { runner.connecting && connect.wizard.unattended }
        XCTAssertTrue(panes.launches.isEmpty, "no terminal for the server")
        XCTAssertEqual(connect.wizard.stage, .details)

        await fill(connect)
        connect.wizard.next()
        XCTAssertEqual(connect.wizard.stage, .review)
        var added = mac.detection
        added.adminMachine = "acme"
        added.missingPackageMachines = ["acme"]
        mac.detection = added
        await connect.create()

        XCTAssertEqual(ran.calls.map(\.arguments), [[
            "machines", "add", "--name", "acme", "--address", "203.0.113.10", "--fingerprint", serverKey,
            "--password-stdin", "--domain", "example.com", "--yes",
        ]])
        XCTAssertEqual(ran.calls.first?.input, Data("hunter2".utf8))
        XCTAssertEqual(connect.wizard.draft.password.value, "")
        try await waitFor { panes.launches.count == 1 }
        XCTAssertFalse(runner.connecting)
        XCTAssertTrue(panes.launches[0].program.args.contains { $0.contains("packages add devmachine-app --machine acme") })
    }

    func testAnOlderCLIFoundWhenTheWizardOpensFallsBackToTheTerminal() async throws {
        var start = OnboardingDetection(cliFound: true, adminMachine: nil, missingPackageMachines: [], agents: [])
        start.cliVersion = MachineUnattendedAdd.minimumCLIVersion
        let panes = FakePanes()
        let runner = OnboardingRunner(
            home: "/Users/alice", launcher: panes, detect: { [start] _ in start },
            connect: connectModel(version: SemanticVersion(major: 0, minor: 7, patch: 20)))
        await runner.refresh()

        runner.start()

        try await waitFor { panes.launches.count == 1 }
        XCTAssertFalse(runner.connecting)
        XCTAssertTrue(panes.launches[0].program.args.contains { $0.hasSuffix("devmachine setup") })
    }

    func testGoingBackFromTheWizardForgetsThePassword() async throws {
        var start = OnboardingDetection(cliFound: true, adminMachine: nil, missingPackageMachines: [], agents: [])
        start.cliVersion = MachineUnattendedAdd.minimumCLIVersion
        let connect = connectModel()
        let runner = OnboardingRunner(
            home: "/Users/alice", launcher: FakePanes(), detect: { [start] _ in start }, connect: connect)
        await runner.refresh()
        runner.start()
        try await waitFor { runner.connecting && connect.wizard.unattended }
        await fill(connect)

        runner.back()

        XCTAssertFalse(runner.connecting)
        XCTAssertEqual(runner.flow.phase, .start)
        XCTAssertEqual(connect.wizard.draft.password.value, "")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
