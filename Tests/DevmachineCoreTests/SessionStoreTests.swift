import XCTest
@testable import DevmachineCore

private struct FakeRunner: CommandRunner {
    let output: String
    final class Box: @unchecked Sendable { var args: [String]? }
    let box = Box()
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        box.args = args
        return output
    }
}

final class SessionStoreTests: XCTestCase {
    func testMontaSessoesDoWorkspace() throws {
        let fake = FakeRunner(output: """
        dash-claude|2
        @@PANES@@
        dash-claude|claude
        """)
        let store = SessionStore(runner: fake)
        let ws = Workspace(name: "acme", alias: "acme-devmachine")
        let sessions = try store.sessions(for: ws)

        XCTAssertEqual(sessions, [TmuxSession(name: "dash-claude", windows: 2, hasClaude: true)])
        XCTAssertEqual(
            fake.box.args,
            RemoteCommands.sshBaseArgs(alias: "acme-devmachine") + [RemoteCommands.listSessions]
        )
    }

    func testRunExecutaComandoNoAlias() throws {
        let fake = FakeRunner(output: "ok")
        let store = SessionStore(runner: fake)
        let result = try store.run(alias: "acme-devmachine", command: "tmux kill-session -t 'x'")

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(
            fake.box.args,
            RemoteCommands.sshBaseArgs(alias: "acme-devmachine") + ["tmux kill-session -t 'x'"]
        )
    }
}
