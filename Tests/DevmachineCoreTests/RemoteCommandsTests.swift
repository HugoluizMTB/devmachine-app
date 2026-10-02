import XCTest
@testable import DevmachineCore

final class RemoteCommandsTests: XCTestCase {
    override func tearDown() {
        RemoteCommands.SSHAgentSocketPreference.shared.update(nil)
        super.tearDown()
    }

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

    func testSessionDirectoryReadsTheActivePanePath() {
        let command = RemoteCommands.sessionDirectory(session: "web")

        XCTAssertEqual(command, "tmux display-message -p -t 'web' '#{pane_current_path}'")
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

    func testSshAuthSocketPrefersAnExplicitOverride() {
        let socket = RemoteCommands.sshAuthSocket(
            customSocket: "/tmp/custom.sock",
            fileExists: { _ in true },
            environment: ["SSH_AUTH_SOCK": "/tmp/inherited.sock"]
        )
        XCTAssertEqual(socket, "/tmp/custom.sock")
    }

    func testSshAuthSocketIgnoresABlankOverride() {
        let socket = RemoteCommands.sshAuthSocket(
            customSocket: "   ",
            fileExists: { _ in true },
            environment: [:]
        )
        XCTAssertEqual(socket, RemoteCommands.onePasswordSocketPath)
    }

    func testSshAuthSocketFallsBackTo1PasswordWhenItExists() {
        let socket = RemoteCommands.sshAuthSocket(
            customSocket: nil,
            fileExists: { $0 == RemoteCommands.onePasswordSocketPath },
            environment: ["SSH_AUTH_SOCK": "/tmp/inherited.sock"]
        )
        XCTAssertEqual(socket, RemoteCommands.onePasswordSocketPath)
    }

    func testSshAuthSocketFallsBackToTheInheritedSocketWithout1Password() {
        let socket = RemoteCommands.sshAuthSocket(
            customSocket: nil,
            fileExists: { _ in false },
            environment: ["SSH_AUTH_SOCK": "/tmp/inherited.sock"]
        )
        XCTAssertEqual(socket, "/tmp/inherited.sock")
    }

    func testSshAuthSocketIsNilWithNothingToOffer() {
        let socket = RemoteCommands.sshAuthSocket(
            customSocket: nil,
            fileExists: { _ in false },
            environment: [:]
        )
        XCTAssertNil(socket)
    }

    func testSshEnvironmentOmitsTheSocketWhenNoneIsAvailable() {
        let env = RemoteCommands.sshEnvironment(
            customSocket: nil,
            fileExists: { _ in false },
            environment: [:]
        )
        XCTAssertNil(env["SSH_AUTH_SOCK"])
        XCTAssertNotNil(env["HOME"])
    }

    func testSshEnvironmentSetsTheSocketWhenOneIsAvailable() {
        let env = RemoteCommands.sshEnvironment(
            customSocket: "/tmp/custom.sock",
            fileExists: { _ in false },
            environment: [:]
        )
        XCTAssertEqual(env["SSH_AUTH_SOCK"], "/tmp/custom.sock")
    }

    func testTerminalEnvironmentOmitsTheSocketWhenNoneIsAvailable() {
        let env = RemoteCommands.terminalEnvironment(customSocket: nil, fileExists: { _ in false }, environment: [:])
        XCTAssertFalse(env.contains { $0.hasPrefix("SSH_AUTH_SOCK=") })
        XCTAssertTrue(env.contains { $0.hasPrefix("TERM=") })
    }

    func testTerminalEnvironmentSetsTheSocketWhenOneIsAvailable() {
        let env = RemoteCommands.terminalEnvironment(
            customSocket: "/tmp/custom.sock", fileExists: { _ in false }, environment: [:])
        XCTAssertTrue(env.contains("SSH_AUTH_SOCK=/tmp/custom.sock"))
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
            "tmux send-keys -t 'a b' -l -- '/eoq' \\; send-keys -t 'a b' Enter"
        )
    }

    func testSendKeysEndsWithEnter() {
        XCTAssertTrue(RemoteCommands.sendKeys(session: "dash", text: "/bpp").hasSuffix(" Enter"))
    }

    func testSendKeysEscapesSingleQuoteInSessionAndText() {
        XCTAssertEqual(
            RemoteCommands.sendKeys(session: "x'y", text: "echo 'hi'"),
            "tmux send-keys -t 'x'\\''y' -l -- 'echo '\\''hi'\\''' \\; send-keys -t 'x'\\''y' Enter"
        )
    }

    func testSendKeysIsInjectionSafeWithDollarAndSemicolonAndBacktick() {
        XCTAssertEqual(
            RemoteCommands.sendKeys(session: "dash", text: "$(rm -rf /); `whoami`"),
            "tmux send-keys -t 'dash' -l -- '$(rm -rf /); `whoami`' \\; send-keys -t 'dash' Enter"
        )
    }

    func testSSHAgentSocketPreferenceStartsUnset() {
        XCTAssertNil(RemoteCommands.SSHAgentSocketPreference.shared.current())
    }

    func testSSHAgentSocketPreferenceRoundTrips() {
        RemoteCommands.SSHAgentSocketPreference.shared.update("/tmp/pref.sock")
        XCTAssertEqual(RemoteCommands.SSHAgentSocketPreference.shared.current(), "/tmp/pref.sock")
    }

    func testSshEnvironmentDefaultsToTheSharedPreferenceWhenNoCustomSocketIsPassed() {
        RemoteCommands.SSHAgentSocketPreference.shared.update("/tmp/pref.sock")

        let env = RemoteCommands.sshEnvironment(fileExists: { _ in false }, environment: [:])

        XCTAssertEqual(env["SSH_AUTH_SOCK"], "/tmp/pref.sock")
    }

    func testTerminalEnvironmentDefaultsToTheSharedPreferenceWhenNoCustomSocketIsPassed() {
        RemoteCommands.SSHAgentSocketPreference.shared.update("/tmp/pref.sock")

        let env = RemoteCommands.terminalEnvironment(fileExists: { _ in false }, environment: [:])

        XCTAssertTrue(env.contains("SSH_AUTH_SOCK=/tmp/pref.sock"))
    }

    func testRemoteSessionsReportAsTmuxNotXterm() {
        XCTAssertTrue(RemoteCommands.terminalEnvironment().contains("TERM=xterm-256color"))
        XCTAssertTrue(RemoteCommands.terminalEnvironment(term: RemoteCommands.remoteTerm).contains("TERM=tmux-256color"))
        XCTAssertFalse(RemoteCommands.remoteTerm.hasPrefix("xterm"))
    }
}

extension RemoteCommandsTests {
    func testCreateSessionNamesTheDirectory() {
        XCTAssertEqual(
            RemoteCommands.createSession(name: "dash", directory: "~/dev/dash"),
            "tmux new-session -d -s 'dash' -c \"$HOME\"/'dev/dash'")
    }

    func testCreateSessionWithoutADirectoryLandsWhereverTheShellDoes() {
        XCTAssertEqual(
            RemoteCommands.createSession(name: "dash", directory: "  "),
            "tmux new-session -d -s 'dash'")
    }

    func testAnAbsoluteDirectoryIsQuotedWhole() {
        XCTAssertEqual(
            RemoteCommands.createSession(name: "x", directory: "/srv/app"),
            "tmux new-session -d -s 'x' -c '/srv/app'")
    }

    func testAQuoteInThePathCannotEndTheQuoting() {
        XCTAssertTrue(
            RemoteCommands.createSession(name: "x", directory: "/a'b").contains("'/a'\\''b'"))
    }
}

extension RemoteCommandsTests {
    func testRefreshAsksEveryClientOfTheSessionToDrawAgain() {
        XCTAssertEqual(
            RemoteCommands.refreshClient(session: "main"),
            "tmux list-clients -t 'main' -F 'refresh-client -t #{client_name}' | tmux source-file -")
    }

    func testRefreshNeverNamesTheSessionAsTheClient() {
        XCTAssertFalse(RemoteCommands.refreshClient(session: "main").contains("refresh-client -t 'main'"))
    }

    func testIdleCopyModeIsLeftOnlyAtTheBottomWithNothingSelected() {
        XCTAssertEqual(
            RemoteCommands.leaveIdleCopyMode(session: "main"),
            "[ \"$(tmux display-message -p -t 'main' '#{pane_mode}:#{scroll_position}:#{selection_present}')\""
                + " = copy-mode:0:0 ] && tmux send-keys -t 'main' -X cancel")
    }

    func testAQuoteInTheSessionNameCannotEndTheQuotingOfTheCopyModeCheck() {
        let command = RemoteCommands.leaveIdleCopyMode(session: "a'b")
        XCTAssertTrue(command.contains("-p -t 'a'\\''b' "))
        XCTAssertTrue(command.hasSuffix("tmux send-keys -t 'a'\\''b' -X cancel"))
    }

    func testReturningToASessionRepaintsItAndLeavesAnIdleCopyMode() {
        XCTAssertEqual(
            RemoteCommands.returnToSession(session: "main"),
            RemoteCommands.refreshClient(session: "main") + "; "
                + RemoteCommands.leaveIdleCopyMode(session: "main"))
    }
}
