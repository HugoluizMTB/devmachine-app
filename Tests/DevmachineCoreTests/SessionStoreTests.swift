import XCTest
@testable import DevmachineCore

private struct FakeRunner: CommandRunner {
    let output: String
    var stderr = ""
    var exitCode: Int32 = 0
    final class Box: @unchecked Sendable { var args: [String]? }
    let box = Box()
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        box.args = args
        return output
    }
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        box.args = args
        return (output, stderr, exitCode)
    }
}

final class SessionStoreTests: XCTestCase {
    func testBuildsWorkspaceSessions() throws {
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

    func testRunExecutesCommandOnTheAlias() throws {
        let fake = FakeRunner(output: "ok")
        let store = SessionStore(runner: fake)
        let result = try store.run(alias: "acme-devmachine", command: "tmux kill-session -t 'x'")

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(
            fake.box.args,
            RemoteCommands.sshBaseArgs(alias: "acme-devmachine") + ["tmux kill-session -t 'x'"]
        )
    }

    func testSSHAuthDeniedIsAFailureNotAnEmptyList() {
        let fake = FakeRunner(output: "", stderr: "acme-devmachine: Permission denied (publickey).", exitCode: 255)
        let store = SessionStore(runner: fake)
        XCTAssertThrowsError(try store.sessions(for: Workspace(name: "acme", alias: "acme-devmachine"))) { error in
            XCTAssertEqual((error as? SessionStoreError)?.failure, .authDenied)
        }
    }

    func testSSHConnectionRefusedIsUnreachable() {
        let fake = FakeRunner(output: "", stderr: "ssh: connect to host 203.0.113.7 port 22: Connection refused", exitCode: 255)
        let store = SessionStore(runner: fake)
        XCTAssertThrowsError(try store.sessions(for: Workspace(name: "acme", alias: "acme-devmachine"))) { error in
            XCTAssertEqual((error as? SessionStoreError)?.failure, .unreachable)
        }
    }

    func testRemoteCommandExitWithoutTmuxServerIsNoSessions() throws {
        let fake = FakeRunner(output: "@@PANES@@\n", stderr: "no server running on /tmp/tmux-1000/default", exitCode: 1)
        let store = SessionStore(runner: fake)
        XCTAssertEqual(try store.sessions(for: Workspace(name: "acme", alias: "acme-devmachine")), [])
    }
}
