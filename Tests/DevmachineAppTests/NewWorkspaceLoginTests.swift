import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ChangingWorkspaceSource: WorkspaceSource, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Workspace]

    init(_ values: [Workspace]) {
        self.values = values
    }

    func add(_ workspace: Workspace) {
        lock.lock()
        values.append(workspace)
        lock.unlock()
    }

    func workspaces(resolveAlias: (String) -> String) throws -> [Workspace] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class AccountSessionSource: SessionSource, @unchecked Sendable {
    private let lock = NSLock()
    private var accounts: Set<String>
    private var withoutTmux: Set<String> = []

    init(accounts: Set<String>) {
        self.accounts = accounts
    }

    func createAccount(_ workspace: String) {
        lock.lock()
        accounts.insert(workspace)
        lock.unlock()
    }

    func removeTmux(_ workspace: String) {
        lock.lock()
        withoutTmux.insert(workspace)
        lock.unlock()
    }

    func removeAccounts() {
        lock.lock()
        accounts.removeAll()
        lock.unlock()
    }

    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession] {
        lock.lock()
        defer { lock.unlock() }
        guard accounts.contains(workspace.name) else {
            throw SessionStoreError(
                failure: .authDenied, stderr: "\(workspace.name)@203.0.113.7: Permission denied (publickey).")
        }
        if withoutTmux.contains(workspace.name) {
            throw SessionListError(problem: .tmuxMissing, stderr: "")
        }
        return [TmuxSession(name: "dash", windows: 1, harnesses: [])]
    }

    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot {
        LocalSessionSnapshot(sessions: [], harnesses: [:])
    }
}

@MainActor
final class NewWorkspaceLoginTests: XCTestCase {
    private let acme = Workspace(name: "acme", alias: "acme-devmachine")
    private let beta = Workspace(name: "beta", alias: "beta-devmachine")

    private func openApp(
        workspaces: ChangingWorkspaceSource, sessions: AccountSessionSource
    ) async throws -> AppModel {
        let model = AppModel(
            services: DevmachineServices(
                workspaceSource: workspaces, sessionSource: sessions, contextSource: FixtureContextSource()),
            detectSettings: { .empty })
        model.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev", hostAlias: "lab", publicIP: "203.0.113.10", baseDomain: "example.com")
        model.loadWorkspaces(detected: .empty)
        try await waitFor { model.sessionsByAlias[self.acme.alias] != nil }
        return model
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testAWorkspaceAddedByTheCLIBeforeItsSyncDoesNotPausePolling() async throws {
        let workspaces = ChangingWorkspaceSource([acme])
        let sessions = AccountSessionSource(accounts: ["acme"])
        let model = try await openApp(workspaces: workspaces, sessions: sessions)

        workspaces.add(beta)
        model.reloadConfiguration()
        try await waitFor { model.sessionProblems[self.beta.alias] != nil }

        XCTAssertEqual(model.sessionProblems[beta.alias]?.isAwaitingSync, true)
        XCTAssertFalse(model.isPollingPaused)
        XCTAssertFalse(model.offlineAliases.contains(beta.alias))
    }

    func testTheSyncThatCreatesTheAccountConnectsTheNewWorkspace() async throws {
        let workspaces = ChangingWorkspaceSource([acme])
        let sessions = AccountSessionSource(accounts: ["acme"])
        let model = try await openApp(workspaces: workspaces, sessions: sessions)
        workspaces.add(beta)
        model.reloadConfiguration()
        try await waitFor { model.sessionProblems[self.beta.alias] != nil }

        sessions.createAccount("beta")
        model.reloadConfiguration()
        try await waitFor { model.sessionsByAlias[self.beta.alias] != nil }

        XCTAssertNil(model.sessionProblems[beta.alias])
        XCTAssertEqual(model.sessionsByAlias[beta.alias]?.map(\.name), ["dash"])
    }

    func testAWorkspaceThatLoggedInOnceIsRefusedLikeAnyOther() async throws {
        let workspaces = ChangingWorkspaceSource([acme])
        let sessions = AccountSessionSource(accounts: ["acme", "beta"])
        let model = try await openApp(workspaces: workspaces, sessions: sessions)
        workspaces.add(beta)
        model.reloadConfiguration()
        try await waitFor { model.sessionsByAlias[self.beta.alias] != nil }

        sessions.removeAccounts()
        model.refresh(alias: beta.alias)
        try await waitFor { model.sessionProblems[self.beta.alias] != nil }

        XCTAssertEqual(model.sessionProblems[beta.alias]?.isAwaitingSync, false)
        XCTAssertTrue(model.isPollingPaused)
    }

    func testAWorkspaceThatLoggedInWithoutTmuxIsRefusedLikeAnyOther() async throws {
        let workspaces = ChangingWorkspaceSource([acme])
        let sessions = AccountSessionSource(accounts: ["acme", "beta"])
        sessions.removeTmux("beta")
        let model = try await openApp(workspaces: workspaces, sessions: sessions)
        workspaces.add(beta)
        model.reloadConfiguration()
        try await waitFor { model.sessionProblems[self.beta.alias] == .tmuxMissing(detail: "") }

        sessions.removeAccounts()
        model.refresh(alias: beta.alias)
        try await waitFor { model.sessionProblems[self.beta.alias]?.isAwaitingSync == false
            && model.sessionProblems[self.beta.alias] != .tmuxMissing(detail: "") }

        XCTAssertTrue(model.isPollingPaused)
    }
}
