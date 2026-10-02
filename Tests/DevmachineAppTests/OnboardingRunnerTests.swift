import Foundation
import XCTest
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

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
