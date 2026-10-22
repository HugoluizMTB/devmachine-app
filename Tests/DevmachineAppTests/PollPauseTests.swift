import XCTest
import Combine
import DevmachineCore
@testable import DevmachineApp

/// Answers each workspace's session list from a script and counts every
/// login, so a test can prove which workspaces a sweep touched.
private final class ScriptedSessionSource: SessionListSource, @unchecked Sendable {
    var asksAllAtOnce = false
    private let lock = NSLock()
    private var failures: [String: SSHFailure] = [:]
    private var connectionRefused: Set<String> = []
    private var logins: [String] = []

    func failConnectionRefused(_ alias: String) {
        lock.lock()
        failures[alias] = nil
        connectionRefused.insert(alias)
        lock.unlock()
    }

    func fail(_ alias: String, with failure: SSHFailure?) {
        lock.lock()
        failures[alias] = failure
        lock.unlock()
    }

    func calls(_ alias: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return logins.filter { $0 == alias }.count
    }

    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession] {
        lock.lock()
        logins.append(workspace.alias)
        let failure = failures[workspace.alias]
        let refusesConnection = connectionRefused.contains(workspace.alias)
        lock.unlock()
        if refusesConnection {
            throw SessionStoreError(failure: .unreachable, stderr: "ssh: connect to host 203.0.113.7 port 22: Connection refused")
        }
        switch failure {
        case .authDenied?:
            throw SessionStoreError(failure: .authDenied, stderr: "\(workspace.name)@203.0.113.7: Permission denied (publickey).")
        case .unreachable?:
            throw SessionStoreError(failure: .unreachable, stderr: "ssh: connect to host 203.0.113.7 port 22: Operation timed out")
        case .hostKeyRejected?:
            throw SessionStoreError(failure: .hostKeyRejected, stderr: "Host key verification failed.")
        case .loginWaiting?:
            throw SessionStoreError(failure: .loginWaiting, stderr: "the SSH agent has not approved the key yet")
        case .agentRefused?:
            throw SessionStoreError(
                failure: .agentRefused,
                stderr: "sign_and_send_pubkey: signing failed for ED25519 \"/Users/alice/.ssh/id_ed25519\" from agent: "
                    + "agent refused operation\n\(workspace.name)@203.0.113.7: Permission denied (publickey).")
        case nil:
            return [TmuxSession(name: "dash", windows: 1, harnesses: [])]
        }
    }

    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot {
        LocalSessionSnapshot(sessions: [], harnesses: [:])
    }
}

@MainActor
final class PollPauseTests: XCTestCase {
    private let acme = Workspace(name: "acme", alias: "acme-devmachine")
    private let beta = Workspace(name: "beta", alias: "beta-devmachine")
    private let gamma = Workspace(name: "gamma", alias: "gamma-devmachine")

    private func makeModel(_ source: ScriptedSessionSource, machines: [String: String]) -> AppModel {
        let model = AppModel(
            services: DevmachineServices(
                workspaceSource: FixtureWorkspaceSource(values: []), sessionSource: source,
                contextSource: FixtureContextSource()),
            detectSettings: { .empty })
        model.machineForWorkspace = { machines[$0] }
        model.workspaces = [acme, beta, gamma]
        return model
    }

    private func sweep(_ model: AppModel) async throws {
        model.refreshAll()
        try await waitFor { !model.isSweeping }
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    func testARefusedLoginHoldsItsWholeMachineAndNoTimeEndsIt() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        var now = Date()
        model.pauseClock = { now }

        try await sweep(model)

        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertTrue(model.isPollingPaused(alias: beta.alias), "same machine, same server counting refusals")
        XCTAssertFalse(model.isPollingPaused(alias: gamma.alias))
        XCTAssertEqual(model.loginHold(alias: beta.alias)?.reason, .loginRefused)
        XCTAssertEqual(source.calls(beta.alias), 0, "held before its turn in the same sweep")
        XCTAssertEqual(model.sessionsByAlias[gamma.alias]?.map(\.name), ["dash"])
        XCTAssertFalse(model.offlineAliases.contains(acme.alias), "a refused login says nothing about the host")
        XCTAssertFalse(model.showsSessionSkeleton(alias: beta.alias))

        for _ in 0..<5 {
            now = now.addingTimeInterval(PollPause.loginRefusedMaxSeconds * 2)
            try await sweep(model)
        }

        XCTAssertEqual(source.calls(acme.alias), 1)
        XCTAssertEqual(source.calls(beta.alias), 0)
        XCTAssertEqual(source.calls(gamma.alias), 6)
    }

    func testAnUnreachableMachinePausesItsWorkspacesOnly() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])

        try await sweep(model)

        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertTrue(model.isPollingPaused(alias: beta.alias))
        XCTAssertFalse(model.isPollingPaused(alias: gamma.alias))
        XCTAssertEqual(source.calls(beta.alias), 0, "an unreachable machine is not asked again for its next account")
        XCTAssertEqual(source.calls(gamma.alias), 1)
        XCTAssertTrue(model.offlineAliases.contains(beta.alias))
        XCTAssertFalse(model.offlineAliases.contains(gamma.alias))
    }

    func testTheRefreshButtonAsksAnUnreachableMachineAgainAtOnce() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        try await sweep(model)
        source.fail(acme.alias, with: nil)

        model.refreshAllNow()
        try await waitFor { !model.isSweeping }

        XCTAssertEqual(source.calls(acme.alias), 2)
        XCTAssertEqual(source.calls(beta.alias), 1)
        XCTAssertFalse(model.isPollingPaused(alias: acme.alias))
        XCTAssertFalse(model.isPollingPaused(alias: beta.alias))
        XCTAssertEqual(model.sessionsByAlias[beta.alias]?.map(\.name), ["dash"])
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
    }

    func testTheRefreshButtonLeavesARefusedLoginPaused() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        try await sweep(model)

        model.refreshAllNow()
        try await waitFor { !model.isSweeping }

        XCTAssertEqual(source.calls(acme.alias), 1, "each refused login counts toward a ban")
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertEqual(source.calls(gamma.alias), 2)
    }

    func testAnUnreachableWorkspaceWithNoKnownMachinePausesOnlyItself() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = makeModel(source, machines: [:])

        try await sweep(model)

        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertFalse(model.isPollingPaused(alias: beta.alias))
        XCTAssertEqual(source.calls(beta.alias), 1)
        XCTAssertEqual(source.calls(gamma.alias), 1)
    }

    func testNothingAutomaticLogsIntoAPausedWorkspace() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        try await sweep(model)
        XCTAssertEqual(source.calls(acme.alias), 1)

        try await sweep(model)
        try await sweep(model)
        model.refresh(alias: acme.alias)
        model.refreshWorkspaces(onMachine: "main")
        try await settle()

        XCTAssertEqual(source.calls(acme.alias), 1)
        XCTAssertEqual(source.calls(beta.alias), 0)
        XCTAssertGreaterThan(source.calls(gamma.alias), 1)
    }

    func testTryAgainPollsOnceAndARefusalPausesAgain() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        try await sweep(model)

        model.retry(alias: acme.alias)
        try await waitFor { source.calls(self.acme.alias) == 2 }
        try await settle()

        XCTAssertEqual(source.calls(acme.alias), 2)
        XCTAssertEqual(source.calls(beta.alias), 0, "Retry is one attempt for the machine")
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertNotNil(model.loginHold(alias: acme.alias))

        source.fail(acme.alias, with: nil)
        model.retry(alias: beta.alias)
        try await waitFor { model.sessionsByAlias[self.acme.alias] != nil }

        XCTAssertNil(model.loginHold(alias: acme.alias))
        XCTAssertEqual(source.calls(acme.alias), 3, "the first workspace on the machine is the one asked")
        XCTAssertFalse(model.isPollingPaused(alias: acme.alias))
        XCTAssertEqual(model.sessionsByAlias[acme.alias]?.map(\.name), ["dash"])
        try await waitFor { model.sessionsByAlias[self.beta.alias] != nil }
    }

    func testWithNoKnownMachineARefusalPausesTheWorkspaceForAWhile() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: [:])
        try await sweep(model)

        let pause = try XCTUnwrap(model.pollPauses[acme.alias])
        XCTAssertEqual(pause.reason, .loginRefused)
        XCTAssertNil(pause.machine)
        XCTAssertEqual(
            pause.notice(workspace: "acme"),
            "Login refused for acme. Paused checking it for 5 min so its machine doesn't block this Mac's IP.")
        XCTAssertNil(model.pollPauses[beta.alias])
        XCTAssertFalse(model.showsSessionSkeleton(alias: acme.alias))

        var now = Date()
        model.pauseClock = { now }
        now = now.addingTimeInterval(PollPause.loginRefusedSeconds - 1)
        try await sweep(model)
        XCTAssertEqual(source.calls(acme.alias), 1, "still paused one second before the 5 minutes end")
        XCTAssertNotNil(model.pollPauses[acme.alias])

        now = now.addingTimeInterval(2)
        source.fail(acme.alias, with: nil)
        try await sweep(model)

        XCTAssertEqual(source.calls(acme.alias), 2)
        XCTAssertNil(model.pollPauses[acme.alias])
    }

    func testRefusalsInARowDoubleThePauseUpToHalfAnHour() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: [:])
        var now = Date()
        model.pauseClock = { now }

        var seen: [TimeInterval] = []
        for _ in 0..<5 {
            try await sweep(model)
            let pause = try XCTUnwrap(model.pollPauses[acme.alias])
            seen.append(pause.seconds)
            now = pause.until.addingTimeInterval(1)
        }

        XCTAssertEqual(seen, [300, 600, 1200, 1800, 1800])
        XCTAssertEqual(source.calls(acme.alias), 5, "one login per pause, never one per sweep")
        XCTAssertEqual(
            model.pollPauses[acme.alias]?.notice(workspace: "acme"),
            "Login refused for acme. Paused checking it for 30 min so its machine doesn't block this Mac's IP.")
        XCTAssertFalse(model.isPollingPaused(alias: beta.alias), "with no known machine, only that workspace")
        XCTAssertEqual(source.calls(beta.alias), 5)
    }

    func testTryAgainAsksDuringALongPauseAndASuccessResetsTheBackOff() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: [:])
        try await sweep(model)
        model.retry(alias: acme.alias)
        try await waitFor { model.pollPauses[self.acme.alias]?.seconds == 600 }

        source.fail(acme.alias, with: nil)
        model.retry(alias: acme.alias)
        try await waitFor { model.sessionsByAlias[self.acme.alias] != nil }
        XCTAssertEqual(source.calls(acme.alias), 3)
        XCTAssertNil(model.pollPauses[acme.alias])

        source.fail(acme.alias, with: .authDenied)
        try await sweep(model)
        XCTAssertEqual(model.pollPauses[acme.alias]?.seconds, PollPause.loginRefusedSeconds)
    }

    func testALoginRefusedByTheCLIHoldsItsMachineAndTheOtherMachineKeepsBeingAsked() async throws {
        let runner = SessionsCLIRunner(result: (
            #"{"workspaces":["#
                + #"{"name":"acme","machine":"main","sessions":[],"error":{"kind":"login-refused","#
                + #""message":"acme@203.0.113.7: Permission denied (publickey)."}},"#
                + #"{"name":"beta","machine":"main","sessions":[]},"#
                + #"{"name":"gamma","machine":"edge","sessions":[]}]}"#, "", 0))
        let cliSource = CLIFirstSessionSource(
            cli: { DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner) },
            fallback: ScriptedSessionSource())
        let model = AppModel(
            services: DevmachineServices(
                workspaceSource: FixtureWorkspaceSource(values: []), sessionSource: cliSource,
                contextSource: FixtureContextSource()),
            detectSettings: { .empty })
        let machines = ["acme": "main", "beta": "main", "gamma": "edge"]
        model.machineForWorkspace = { machines[$0] }
        model.workspaces = [acme, beta, gamma]

        try await sweep(model)

        XCTAssertEqual(model.loginHold(alias: acme.alias)?.reason, .loginRefused)
        XCTAssertEqual(model.loginHold(alias: acme.alias)?.detail, "acme@203.0.113.7: Permission denied (publickey).")
        XCTAssertTrue(model.isPollingPaused(alias: beta.alias))
        XCTAssertFalse(model.offlineAliases.contains(beta.alias))
        XCTAssertFalse(model.offlineAliases.contains(acme.alias), "a refused login says nothing about the host")

        try await sweep(model)

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls.last, ["--format", "json", "sessions", "--workspace", "gamma"])
    }

    func testAWorkspaceTheLockDoesNotNameIsNotAskedUntilASyncNamesIt() async throws {
        let source = ScriptedSessionSource()
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        model.applySyncLock(PackagesLock(machines: [:], workspaces: ["beta": [], "gamma": []]))

        try await sweep(model)
        try await sweep(model)
        model.refresh(alias: acme.alias)
        try await settle()

        XCTAssertEqual(source.calls(acme.alias), 0)
        XCTAssertEqual(source.calls(beta.alias), 2)
        XCTAssertEqual(model.sessionProblems[acme.alias]?.isAwaitingSync, true)
        XCTAssertTrue(model.pollPauses.isEmpty)
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
        XCTAssertFalse(model.showsSessionSkeleton(alias: acme.alias))

        model.applySyncLock(PackagesLock(machines: [:], workspaces: ["acme": [], "beta": [], "gamma": []]))
        try await waitFor { model.sessionsByAlias[self.acme.alias] != nil }

        XCTAssertEqual(source.calls(acme.alias), 1)
        XCTAssertNil(model.sessionProblems[acme.alias])
    }

    func testTryAgainAsksAnUnsyncedWorkspaceOnceAndARefusalWaitsForTheSyncAgain() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        model.applySyncLock(PackagesLock(machines: [:], workspaces: ["beta": [], "gamma": []]))

        model.retry(alias: acme.alias)
        try await waitFor { source.calls(self.acme.alias) == 1 }
        try await settle()
        try await sweep(model)

        XCTAssertEqual(source.calls(acme.alias), 1)
        XCTAssertEqual(model.sessionProblems[acme.alias]?.isAwaitingSync, true)
        XCTAssertNil(model.pollPauses[acme.alias], "a missing account is not a locked agent")
        XCTAssertFalse(model.isPollingPaused(alias: beta.alias))
    }

    func testASyncOnItsWayReplacesTheFirstSyncCard() async throws {
        let model = makeModel(ScriptedSessionSource(), machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        model.applySyncLock(PackagesLock(machines: [:], workspaces: ["beta": [], "gamma": []]))
        let start = Date()

        XCTAssertNil(model.firstSyncActivity(alias: acme.alias, machine: "main"))
        XCTAssertNil(model.firstSyncActivity(alias: beta.alias, machine: "main"), "beta is synced")

        model.applyLocalSyncs([LocalSync(pid: 7, machine: "edge", byOperator: true)], at: start)
        XCTAssertNil(model.firstSyncActivity(alias: acme.alias, machine: "main"), "another machine's sync")

        model.applyLocalSyncs([LocalSync(pid: 8, machine: nil, byOperator: true)], at: start)
        XCTAssertEqual(model.firstSyncActivity(alias: acme.alias, machine: "main"), .operatorWorking)

        model.applyLocalSyncs([], at: start.addingTimeInterval(AppModel.localSyncGrace - 1))
        XCTAssertEqual(model.firstSyncActivity(alias: acme.alias, machine: "main"), .operatorWorking,
                       "the gap between the dry run and the apply")

        model.applyLocalSyncs([], at: start.addingTimeInterval(AppModel.localSyncGrace + 1))
        XCTAssertNil(model.firstSyncActivity(alias: acme.alias, machine: "main"))

        model.applyLocalSyncs([LocalSync(pid: 9, machine: "main", byOperator: false)], at: start)
        XCTAssertEqual(model.firstSyncActivity(alias: acme.alias, machine: "main"), .localSync)
    }

    func testASyncWaitingToBeStartedLeavesTheFirstSyncCard() async throws {
        let model = makeModel(ScriptedSessionSource(), machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        model.applySyncLock(PackagesLock(machines: [:], workspaces: ["beta": [], "gamma": []]))

        model.jobs.requestSync(SyncRequest(machine: "main"))
        try await settle()

        XCTAssertTrue(model.activeJobMachines.isEmpty)
        XCTAssertNil(model.firstSyncActivity(alias: acme.alias, machine: "main"))
    }

    func testALockThatNamesNoWorkspaceHoldsNothingBack() async throws {
        let source = ScriptedSessionSource()
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        model.applySyncLock(PackagesLock(machines: ["main": []]))

        try await sweep(model)

        XCTAssertEqual(source.calls(acme.alias), 1)
        XCTAssertNil(model.sessionProblems[acme.alias])
    }

    func testAWorkspaceThatAnsweredIsAskedWhateverTheLockSays() async throws {
        let source = ScriptedSessionSource()
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        try await sweep(model)

        model.applySyncLock(PackagesLock(machines: [:], workspaces: ["beta": [], "gamma": []]))
        try await sweep(model)

        XCTAssertEqual(source.calls(acme.alias), 2)
        XCTAssertNil(model.sessionProblems[acme.alias])
    }

    func testAnUnreachableMachineSaysSoWithoutTheBanWarning() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        try await sweep(model)

        let pause = try XCTUnwrap(model.pollPauses[beta.alias])
        XCTAssertEqual(pause.reason, .unreachable)
        XCTAssertEqual(pause.notice(workspace: "beta"), "Couldn't reach main. Paused checking its workspaces for 1 min.")
        XCTAssertFalse(pause.notice(workspace: "beta").contains("IP"))
        XCTAssertEqual(
            PollPause(reason: .unreachable, machine: nil, until: .distantFuture).notice(workspace: "acme"),
            "Couldn't reach acme. Paused checking it for 1 min.")

        var now = Date()
        model.pauseClock = { now }
        now = now.addingTimeInterval(PollPause.unreachableSeconds + 1)
        source.fail(acme.alias, with: nil)
        try await sweep(model)

        XCTAssertNil(model.pollPauses[acme.alias])
        XCTAssertNil(model.pollPauses[beta.alias])
        XCTAssertEqual(source.calls(beta.alias), 1)
    }

    func testARefusedHostKeyStillPausesNothing() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .hostKeyRejected)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])

        try await sweep(model)

        XCTAssertTrue(model.pollPauses.isEmpty)
        XCTAssertEqual(model.sessionProblems[acme.alias]?.isHostKeyRejected, true)
        XCTAssertEqual(source.calls(beta.alias), 1)
    }

    func testALoginRefusedOutsideTheSweepHoldsItsMachine() {
        let model = makeModel(ScriptedSessionSource(), machines: ["acme": "main", "beta": "main"])

        model.noteSSHFailure(alias: acme.alias, .hostKeyRejected)
        XCTAssertFalse(model.isPollingPaused(alias: acme.alias), "a refused host key tried no login")

        model.noteSSHFailure(alias: acme.alias, .authDenied)
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertTrue(model.isPollingPaused(alias: beta.alias))

        model.noteSSHFailure(alias: gamma.alias, .unreachable)
        XCTAssertTrue(model.isPollingPaused(alias: gamma.alias))
    }

    func testARefusalOnAnotherMachineHoldsOnlyThatMachine() async throws {
        let source = ScriptedSessionSource()
        source.fail(gamma.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])

        try await sweep(model)
        try await sweep(model)

        XCTAssertEqual(model.loginHold(alias: gamma.alias)?.reason, .loginRefused)
        XCTAssertNil(model.loginHold(alias: acme.alias))
        XCTAssertEqual(source.calls(acme.alias), 2)
        XCTAssertEqual(source.calls(beta.alias), 2)
        XCTAssertEqual(source.calls(gamma.alias), 1)
    }

    func testAConnectionRefusedAfterARefusedLoginReadsAsABlock() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        try await sweep(model)

        source.failConnectionRefused(acme.alias)
        model.retry(alias: acme.alias)
        try await waitFor { model.loginHold(alias: self.acme.alias)?.reason == .probablyBlocked }
        try await sweep(model)

        XCTAssertEqual(source.calls(acme.alias), 2)
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
        XCTAssertEqual(
            model.loginHold(alias: beta.alias)?.message,
            "The server may be blocking this Mac after failed logins. Wait about 10 minutes, then Retry.")
    }

    func testARetryWithNothingToAskLeavesTheHoldAndAnotherRetryPossible() async throws {
        let source = ScriptedSessionSource()
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        var asked: [String] = []
        model.attemptWithoutWorkspace = { asked.append($0); return false }
        model.noteSSHFailure(alias: acme.alias, .authDenied)
        model.applySyncLock(PackagesLock(machines: [:], workspaces: ["gamma": []]))

        model.retry(alias: acme.alias)
        model.retry(alias: beta.alias)
        try await settle()

        XCTAssertEqual(asked, ["main", "main"], "each Retry gets its own attempt")
        XCTAssertFalse(model.loginHolds.holds.isRetrying("main"))
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertEqual(source.calls(acme.alias) + source.calls(beta.alias), 0)
    }

    func testAChangedMachineEntryEndsTheHoldAndAsksAtOnce() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        model.loginHolds.configurationRead(["main": "203.0.113.7|alice|22||", "edge": "203.0.113.8|bob|22||"])
        try await sweep(model)
        source.fail(acme.alias, with: nil)

        model.loginHolds.configurationRead(["main": "203.0.113.7|alice|22||", "edge": "203.0.113.8|bob|22||"])
        try await settle()
        XCTAssertEqual(source.calls(acme.alias), 1, "the same entry read again changes nothing")

        model.loginHolds.configurationRead(["main": "203.0.113.7|alice|22|/Users/alice/.ssh/main|", "edge": "203.0.113.8|bob|22||"])
        try await waitFor { model.sessionsByAlias[self.beta.alias] != nil && model.sessionsByAlias[self.acme.alias] != nil }

        XCTAssertNil(model.loginHold(alias: acme.alias))
        XCTAssertEqual(source.calls(acme.alias), 2)
        XCTAssertEqual(source.calls(beta.alias), 1)
    }

    func testTheToastShowsOnceWhenAPauseStarts() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = makeModel(source, machines: [:])
        let notice = "Login refused for acme. Paused checking it for 5 min so its machine doesn't block this Mac's IP."
        let toasts = toastCounter(model, label: notice)
        defer { toasts.cancel() }

        try await sweep(model)
        XCTAssertEqual(toasts.count, 1)

        try await sweep(model)
        var now = Date()
        model.pauseClock = { now }
        now = now.addingTimeInterval(PollPause.loginRefusedSeconds + 1)
        try await sweep(model)

        XCTAssertEqual(source.calls(acme.alias), 2, "the pause ended and the sweep asked again")
        XCTAssertEqual(toasts.count, 1, "a pause that goes on is not announced again")
    }

    func testAnUnreachableMachineIsAnnouncedOnce() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        let toasts = toastCounter(model, label: "Couldn't reach main. Paused checking its workspaces for 1 min.")
        defer { toasts.cancel() }

        try await sweep(model)

        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(model.activeTasks.filter { $0.label.contains("beta") }.count, 0)
    }

    /// Counts each corner card with this label once, however long it stays.
    private final class ToastCounter {
        var ids: Set<UUID> = []
        var token: AnyCancellable?
        var count: Int { ids.count }
        func cancel() { token?.cancel() }
    }

    private func toastCounter(_ model: AppModel, label: String) -> ToastCounter {
        let counter = ToastCounter()
        counter.token = model.$activeTasks.sink { tasks in
            for task in tasks where task.label == label { counter.ids.insert(task.id) }
        }
        return counter
    }

    func testAPausedWorkspaceHoldsTheContextPollButNotItsRetry() async throws {
        let source = FixtureContextSource()
        let store = ContextStore(services: fixtureServices(context: source))
        defer { store.stop() }
        store.holdsReads = { _ in true }
        let target = CommandTarget.remote(alias: acme.alias, session: "dash")

        store.start(target)
        try await settle()
        XCTAssertTrue(source.calls.isEmpty)

        store.retry()
        try await waitFor { source.calls == [target] }
    }

    private func wakeModel(_ source: ScriptedSessionSource) -> AppModel {
        let model = makeModel(source, machines: ["acme": "main", "beta": "main", "gamma": "edge"])
        model.wakeSweepDelay = 60
        model.networkSweepDelay = 0
        return model
    }

    func testWaitingForTheAgentIsNotOfflineAndPausesNothing() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .loginWaiting)
        let model = wakeModel(source)

        try await sweep(model)

        XCTAssertEqual(model.sessionProblems[acme.alias]?.isLoginWaiting, true)
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
        XCTAssertFalse(model.isPollingPaused(alias: acme.alias))
        XCTAssertFalse(model.isPollingPaused(alias: beta.alias))

        source.fail(acme.alias, with: nil)
        try await sweep(model)
        XCTAssertNil(model.sessionProblems[acme.alias])
    }

    func testAnAgentThatWillNotSignPausesQuietlyAndHoldsNothing() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: nil)
        let model = wakeModel(source)
        try await sweep(model)
        XCTAssertEqual(model.sessionsByAlias[acme.alias]?.map(\.name), ["dash"])

        source.fail(acme.alias, with: .agentRefused)
        source.fail(gamma.alias, with: .agentRefused)
        let toasts = toastCounter(model, label: PollPause(.agentLocked, machine: "main", from: Date()).notice(workspace: "acme"))
        defer { toasts.cancel() }
        try await sweep(model)

        XCTAssertNil(model.loginHold(alias: acme.alias), "the machine refused nothing")
        XCTAssertNil(model.loginHold(alias: gamma.alias))
        XCTAssertEqual(model.pollPauses[acme.alias]?.reason, .agentLocked)
        XCTAssertEqual(model.pollPauses[beta.alias]?.reason, .agentLocked, "its sibling on the same machine waits too")
        XCTAssertEqual(model.pollPauses[gamma.alias]?.reason, .agentLocked)
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
        XCTAssertNil(model.sessionProblems[acme.alias])
        XCTAssertNil(model.sessionProblems[beta.alias])
        XCTAssertEqual(model.sessionsByAlias[acme.alias]?.map(\.name), ["dash"], "the sessions it knew stay on screen")
        XCTAssertEqual(toasts.count, 0, "nothing is announced")
    }

    func testComingBackToTheAppEndsTheAgentPauseAndAsksAgain() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .agentRefused)
        let model = wakeModel(source)
        try await sweep(model)
        XCTAssertEqual(model.pollPauses[acme.alias]?.reason, .agentLocked)
        let before = source.calls(acme.alias)

        source.fail(acme.alias, with: nil)
        model.sweepClock = { Date().addingTimeInterval(60) }
        model.appBecameActive()
        try await waitFor { source.calls(self.acme.alias) > before && !model.isSweeping }

        XCTAssertNil(model.pollPauses[acme.alias])
        XCTAssertNil(model.pollPauses[beta.alias])
        XCTAssertEqual(model.sessionsByAlias[acme.alias]?.map(\.name), ["dash"])
    }

    func testTheAgentPauseEndsOnItsOwnAfterAWhile() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .agentRefused)
        let model = wakeModel(source)
        try await sweep(model)
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))

        model.pauseClock = { Date().addingTimeInterval(PollPause.agentLockedSeconds + 1) }
        XCTAssertFalse(model.isPollingPaused(alias: acme.alias))
    }

    func testWakingWaitsForTheNetworkBeforeItSweeps() async throws {
        let source = ScriptedSessionSource()
        let model = wakeModel(source)

        model.resumePollingAfterWake()
        try await settle()
        XCTAssertEqual(source.calls(acme.alias), 0)

        model.networkReturned()
        try await waitFor { source.calls(self.acme.alias) == 1 }
    }

    func testAMachineThatDoesNotAnswerRightAfterAWakeIsReconnectingNotOffline() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = wakeModel(source)
        model.resumePollingAfterWake()

        try await sweep(model)

        XCTAssertEqual(model.pollPauses[acme.alias]?.reason, .reconnecting)
        XCTAssertEqual(model.pollPauses[acme.alias]?.seconds, PollPause.reconnectingSeconds)
        XCTAssertEqual(model.pollPauses[beta.alias]?.reason, .reconnecting)
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
        XCTAssertFalse(model.offlineAliases.contains(beta.alias))
    }

    func testAfterTheGraceAMachineThatDoesNotAnswerIsOffline() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = wakeModel(source)
        var now = Date()
        model.pauseClock = { now }
        model.resumePollingAfterWake()
        now = now.addingTimeInterval(AppModel.reconnectGraceSeconds + 1)

        try await sweep(model)

        XCTAssertEqual(model.pollPauses[acme.alias]?.reason, .unreachable)
        XCTAssertTrue(model.offlineAliases.contains(acme.alias))
    }

    func testTheNetworkComingBackLiftsAnUnreachablePause() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = wakeModel(source)
        try await sweep(model)
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))

        source.fail(acme.alias, with: nil)
        model.networkReturned()

        try await waitFor { model.sessionsByAlias[self.acme.alias] != nil && !model.isSweeping }
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
    }

    func testTheNetworkComingBackKeepsARefusedLoginPaused() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .authDenied)
        let model = wakeModel(source)
        try await sweep(model)

        model.networkReturned()
        try await settle()

        XCTAssertEqual(source.calls(acme.alias), 1)
        XCTAssertTrue(model.isPollingPaused(alias: acme.alias))
    }

    func testAnOpenTerminalThatJustSpokeKeepsItsMachineFromTurningRed() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = wakeModel(source)
        model.terminalHeardFrom = { $0 == self.beta.alias ? Date() : nil }

        try await sweep(model)

        XCTAssertEqual(model.pollPauses[acme.alias]?.reason, .reconnecting)
        XCTAssertFalse(model.offlineAliases.contains(acme.alias))
    }

    func testATerminalSilentForLongProvesNothing() async throws {
        let source = ScriptedSessionSource()
        source.fail(acme.alias, with: .unreachable)
        let model = wakeModel(source)
        model.terminalHeardFrom = { $0 == self.beta.alias ? Date().addingTimeInterval(-600) : nil }

        try await sweep(model)

        XCTAssertEqual(model.pollPauses[acme.alias]?.reason, .unreachable)
        XCTAssertTrue(model.offlineAliases.contains(acme.alias))
    }

    func testInTheBackgroundTheSweepRunsLessOften() async throws {
        let source = ScriptedSessionSource()
        source.asksAllAtOnce = true
        let model = wakeModel(source)
        var now = Date()
        model.sweepClock = { now }
        model.appIsActive = { false }
        try await sweep(model)

        now = now.addingTimeInterval(10)
        model.tick()
        try await settle()
        XCTAssertEqual(source.calls(acme.alias), 1)

        now = now.addingTimeInterval(AppModel.backgroundSweepSeconds)
        model.tick()
        try await waitFor { source.calls(self.acme.alias) == 2 }
    }

    func testComingBackToTheAppSweepsAtOnce() async throws {
        let source = ScriptedSessionSource()
        source.asksAllAtOnce = true
        let model = wakeModel(source)
        var now = Date()
        model.sweepClock = { now }
        model.appIsActive = { false }
        try await sweep(model)

        now = now.addingTimeInterval(10)
        model.appIsActive = { true }
        model.appBecameActive()

        try await waitFor { source.calls(self.acme.alias) == 2 }
    }
}
