import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

final class ContextBridgeTests: XCTestCase {
    private let workspaces = [
        Workspace(name: "alice-dev", alias: "alice-dev-devmachine", kind: .remote),
        Workspace(name: "bob-dev", alias: "bob-dev-devmachine", kind: .remote),
    ]

    private func state(cwd: String, claude: Bool) -> ContextState {
        ContextState(cwd: cwd, isClaude: claude, updatedAt: "2026-10-07T10:00:00Z", plan: nil, prs: [], links: [])
    }

    func testARemoteSessionGivesItsWorkspaceMachinePathAndHarness() {
        let facts = ContextBridge.facts(
            selection: .session(alias: "bob-dev-devmachine", name: "api"), workspaces: workspaces,
            machineForWorkspace: { $0 == "bob-dev" ? "main" : nil }, selfMachine: "here",
            state: state(cwd: "/home/bob/api", claude: true), git: ContextGitStatus(branch: "main", repo: "acme/api"))
        XCTAssertEqual(facts, SessionContextFacts(
            machine: "main", session: "api", workspace: "bob-dev", path: "/home/bob/api", repo: "acme/api",
            branch: "main", harness: "claude"))
    }

    func testALocalSessionIsOnTheSelfMachineInItsFolder() {
        let facts = ContextBridge.facts(
            selection: .localSession(name: "notes", path: "/Users/alice/notes"), workspaces: workspaces,
            machineForWorkspace: { _ in "main" }, selfMachine: "here", state: nil, git: nil)
        XCTAssertEqual(facts, SessionContextFacts(machine: "here", session: "notes", path: "/Users/alice/notes"))
    }

    func testNothingSelectedGivesEmptyKeys() {
        let facts = ContextBridge.facts(
            selection: nil, workspaces: workspaces, machineForWorkspace: { _ in "main" }, selfMachine: nil,
            state: nil, git: nil)
        XCTAssertEqual(facts, SessionContextFacts())
        XCTAssertEqual(facts.values.count, 7)
    }

    func testAnUnknownWorkspaceOrMachineIsEmptyNotAGuess() {
        let facts = ContextBridge.facts(
            selection: .session(alias: "ghost-devmachine", name: "api"), workspaces: workspaces,
            machineForWorkspace: { _ in nil }, selfMachine: "here", state: nil, git: nil)
        XCTAssertEqual(facts.workspace, "")
        XCTAssertEqual(facts.machine, "")
        XCTAssertEqual(facts.session, "api")
    }
}
