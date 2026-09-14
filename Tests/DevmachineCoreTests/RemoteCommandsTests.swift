import XCTest
@testable import DevmachineCore

final class RemoteCommandsTests: XCTestCase {
    func testListSessionsHasSentinelAndDelimiter() {
        let c = RemoteCommands.listSessions
        XCTAssertTrue(c.contains("list-sessions"))
        XCTAssertTrue(c.contains(RemoteCommands.paneSentinel))
        XCTAssertTrue(c.contains("#S|#{session_windows}"))
        XCTAssertTrue(c.contains("list-panes -a"))
    }

    func testAttachAndNewSessionNeverKill() {
        XCTAssertEqual(RemoteCommands.attach(session: "dash"), "tmux attach -t dash")
        XCTAssertEqual(RemoteCommands.newSession(name: "nova"), "tmux new-session -A -s 'nova'")
        XCTAssertFalse(RemoteCommands.attach(session: "x").contains("kill"))
    }

    func testNewSessionEscapesNameWithSpace() {
        XCTAssertEqual(
            RemoteCommands.newSession(name: "a b"),
            "tmux new-session -A -s 'a b'"
        )
    }

    func testNewSessionEscapesSingleQuote() {
        XCTAssertEqual(
            RemoteCommands.newSession(name: "x'y"),
            "tmux new-session -A -s 'x'\\''y'"
        )
    }

    func testSshBaseArgsPutAliasFirstThenOptions() {
        XCTAssertEqual(
            RemoteCommands.sshBaseArgs(alias: "acme-devmachine"),
            [
                "acme-devmachine",
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                "-o", "ServerAliveInterval=5",
                "-o", "ServerAliveCountMax=2"
            ]
        )
    }

    func testSshEnvironmentHasThe1PasswordSocket() {
        let env = RemoteCommands.sshEnvironment()
        XCTAssertEqual(env["SSH_AUTH_SOCK"], RemoteCommands.onePasswordSocketPath)
        XCTAssertNotNil(env["HOME"])
    }

    func testRenameEscapesBothNames() {
        XCTAssertEqual(
            RemoteCommands.rename(session: "old", to: "new"),
            "tmux rename-session -t 'old' 'new'"
        )
        XCTAssertEqual(
            RemoteCommands.rename(session: "x'y", to: "a b"),
            "tmux rename-session -t 'x'\\''y' 'a b'"
        )
    }

    func testKillSessionEscapesName() {
        XCTAssertEqual(
            RemoteCommands.killSession(name: "dash"),
            "tmux kill-session -t 'dash'"
        )
        XCTAssertEqual(
            RemoteCommands.killSession(name: "x'y"),
            "tmux kill-session -t 'x'\\''y'"
        )
    }

    func testSendKeysSingleQuotesSessionAndText() {
        XCTAssertEqual(
            RemoteCommands.sendKeys(session: "a b", text: "/eoq"),
            "tmux send-keys -t 'a b' -- '/eoq' Enter"
        )
    }

    func testSendKeysEndsWithEnter() {
        XCTAssertTrue(RemoteCommands.sendKeys(session: "dash", text: "/bpp").hasSuffix(" Enter"))
    }

    func testSendKeysEscapesSingleQuoteInSessionAndText() {
        XCTAssertEqual(
            RemoteCommands.sendKeys(session: "x'y", text: "echo 'hi'"),
            "tmux send-keys -t 'x'\\''y' -- 'echo '\\''hi'\\''' Enter"
        )
    }

    func testSendKeysIsInjectionSafeWithDollarAndSemicolonAndBacktick() {
        XCTAssertEqual(
            RemoteCommands.sendKeys(session: "dash", text: "$(rm -rf /); `whoami`"),
            "tmux send-keys -t 'dash' -- '$(rm -rf /); `whoami`' Enter"
        )
    }
}
