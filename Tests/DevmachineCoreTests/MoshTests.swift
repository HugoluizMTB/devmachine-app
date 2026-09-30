import XCTest
@testable import DevmachineCore

final class MoshBootstrapTests: XCTestCase {
    func testTheServerCommandStartsTmuxThroughMoshServer() {
        XCTAssertEqual(
            MoshBootstrap.serverCommand(session: "dev"),
            "mosh-server new -s -c 256 -l LANG=C.UTF-8 -- tmux new-session -A -s 'dev'")
    }

    func testTheSessionNameIsQuotedForTheRemoteShell() {
        XCTAssertEqual(
            MoshBootstrap.serverCommand(session: "it's; rm -rf ~"),
            "mosh-server new -s -c 256 -l LANG=C.UTF-8 -- tmux new-session -A -s 'it'\\''s; rm -rf ~'")
    }

    func testTheSSHArgumentsRunTheServerCommandWithoutATerminal() {
        let args = MoshBootstrap.sshArguments(alias: "acme-devmachine", session: "dev")
        XCTAssertEqual(args.first, "acme-devmachine")
        XCTAssertTrue(args.contains("BatchMode=yes"))
        XCTAssertTrue(args.contains("-T"))
        XCTAssertTrue(args.contains("-n"))
        XCTAssertEqual(Array(args.suffix(2)), ["--", MoshBootstrap.serverCommand(session: "dev")])
    }

    func testReadsPortKeyAndServerPid() {
        let outcome = MoshBootstrap.parse(
            stdout: "\nMOSH CONNECT 60001 AbCdEfGhIjKlMnOpQrStUv\n",
            stderr: "\nmosh-server (mosh 1.4.0) [build mosh 1.4.0]\n[mosh-server detached, pid = 4242]\n",
            exitCode: 0)
        XCTAssertEqual(
            outcome, .ready(MoshSession(port: 60001, key: "AbCdEfGhIjKlMnOpQrStUv", serverPID: 4242)))
    }

    func testNoisyLoginLinesBeforeTheConnectLineAreIgnored() {
        let stdout = """
        Welcome to Ubuntu 24.04 LTS
        MOSH CONNECT is a string in this banner, not a real line
         * Documentation:  https://help.example.com
        \r
        MOSH CONNECT 60007 0123456789abcdefGHIJ+/\r
        """
        let outcome = MoshBootstrap.parse(stdout: stdout, stderr: "", exitCode: 0)
        XCTAssertEqual(outcome, .ready(MoshSession(port: 60007, key: "0123456789abcdefGHIJ+/", serverPID: nil)))
    }

    func testAMissingMoshServerIsNoServer() {
        XCTAssertEqual(
            MoshBootstrap.parse(stdout: "", stderr: "bash: line 1: mosh-server: command not found\n", exitCode: 127),
            .noServer("bash: line 1: mosh-server: command not found"))
        XCTAssertEqual(
            MoshBootstrap.parse(stdout: "", stderr: "sh: 1: mosh-server: not found", exitCode: 127),
            .noServer("sh: 1: mosh-server: not found"))
    }

    func testAnSSHFailureIsUnreachable() {
        XCTAssertEqual(
            MoshBootstrap.parse(stdout: "", stderr: "ssh: connect to host 203.0.113.10 port 22: Operation timed out", exitCode: 255),
            .unreachable("ssh: connect to host 203.0.113.10 port 22: Operation timed out"))
    }

    func testAServerThatRanButNeverConnectedIsServerFailed() {
        let stderr = "mosh-server needs a UTF-8 native locale to run."
        XCTAssertEqual(
            MoshBootstrap.parse(stdout: "", stderr: stderr, exitCode: 1), .serverFailed(stderr))
    }

    func testAMalformedKeyIsNotAConnectLine() {
        let outcome = MoshBootstrap.parse(stdout: "MOSH CONNECT 60001 short\n", stderr: "", exitCode: 0)
        XCTAssertEqual(outcome, .serverFailed("MOSH CONNECT 60001 short"))
    }

    func testTheClientGetsTheKeyOnlyThroughItsEnvironment() {
        let session = MoshSession(port: 60001, key: "AbCdEfGhIjKlMnOpQrStUv", serverPID: nil)
        XCTAssertEqual(MoshBootstrap.clientArguments(ip: "203.0.113.10", session: session), ["203.0.113.10", "60001"])
        let env = MoshBootstrap.clientEnvironment(session: session, base: ["TERM=tmux-256color"])
        XCTAssertEqual(env, ["TERM=tmux-256color", "MOSH_KEY=AbCdEfGhIjKlMnOpQrStUv"])
    }

    func testTheSSHFallbackEndsTheServerThatNobodyWillReach() {
        XCTAssertEqual(
            MoshBootstrap.sshFallbackCommand(session: "dev", strayServerPID: 4242),
            "kill 4242 2>/dev/null; tmux new-session -A -s 'dev'")
        XCTAssertEqual(
            MoshBootstrap.sshFallbackCommand(session: "dev", strayServerPID: nil),
            "tmux new-session -A -s 'dev'")
    }
}

final class MoshClientProbeTests: XCTestCase {
    func testTheMarkerMatchesWhatMoshClientDrawsWhileNothingCameBack() {
        let topRow = "mosh: Nothing received from server on UDP port 60001. [To quit: Ctrl-^ .]"
        XCTAssertTrue(topRow.contains(MoshClientProbe.connectingMarker))
        XCTAssertEqual(MoshClientProbe.timeout, 5)
    }
}

final class MoshClientLocatorTests: XCTestCase {
    func testTheBundledClientWins() {
        let path = MoshClientLocator.path(
            bundled: "/Applications/Devmachine.app/Contents/Helpers/mosh-client",
            exists: { _ in true })
        XCTAssertEqual(path, "/Applications/Devmachine.app/Contents/Helpers/mosh-client")
    }

    func testAppleSiliconHomebrewIsTheFirstFallback() {
        let path = MoshClientLocator.path(bundled: nil, exists: { _ in true })
        XCTAssertEqual(path, "/opt/homebrew/bin/mosh-client")
    }

    func testIntelHomebrewIsTheSecondFallback() {
        let path = MoshClientLocator.path(
            bundled: "/missing/mosh-client", exists: { $0 == "/usr/local/bin/mosh-client" })
        XCTAssertEqual(path, "/usr/local/bin/mosh-client")
    }

    func testNoClientAnywhere() {
        XCTAssertNil(MoshClientLocator.path(bundled: "/missing/mosh-client", exists: { _ in false }))
    }
}

final class MoshAddressTests: XCTestCase {
    func testResolveIsSupportedWhenItsHelpSucceeds() {
        XCTAssertTrue(MoshAddress.supportsResolve(exitCode: 0, output: "Usage:\n  devmachine resolve [flags]"))
        XCTAssertFalse(MoshAddress.supportsResolve(exitCode: 1, output: "Error: unknown command \"resolve\""))
        XCTAssertFalse(MoshAddress.supportsResolve(exitCode: 0, output: "Usage:\n  devmachine [command]"))
    }

    func testTheResolveArgumentsNameTheMachine() {
        XCTAssertEqual(
            MoshAddress.resolveArguments(machine: "main"),
            ["resolve", "--machine", "main", "--format", "json"])
    }

    func testReadsTheAddressesInTryOrder() {
        let json = """
        {"machine":"main","addresses":[
          {"address":"100.64.0.5","source":"tailscale:main","package":"tailscale"},
          {"address":"203.0.113.10","source":"203.0.113.10","package":""}],
         "dropped":[{"source":"tailscale:vps","reason":"tailscale is not running"}]}
        """
        XCTAssertEqual(MoshAddress.addresses(fromResolveJSON: json), ["100.64.0.5", "203.0.113.10"])
    }

    func testAnAddressThatIsNotAnIPIsSkipped() {
        let json = #"{"addresses":[{"address":"main.example.com"},{"address":"203.0.113.10"}]}"#
        XCTAssertEqual(MoshAddress.addresses(fromResolveJSON: json), ["203.0.113.10"])
    }

    func testAnUnknownShapeFallsBackToAnyIPField() {
        XCTAssertEqual(MoshAddress.addresses(fromResolveJSON: #"{"machine":{"ip":"100.64.0.7"}}"#), ["100.64.0.7"])
        XCTAssertEqual(MoshAddress.addresses(fromResolveJSON: "not json"), [])
    }

    func testReadsTheHostnameSSHWouldUse() {
        let config = "user alice\nhostname 203.0.113.10\nport 22\n"
        XCTAssertEqual(MoshAddress.hostname(fromSSHConfig: config), "203.0.113.10")
        XCTAssertNil(MoshAddress.hostname(fromSSHConfig: "user alice\n"))
    }

    func testAnIPIsUsedAsIsAndANameIsLookedUpPreferringIPv4() {
        XCTAssertEqual(MoshAddress.ip(for: "203.0.113.10", lookup: { _ in XCTFail(); return [] }), "203.0.113.10")
        XCTAssertEqual(
            MoshAddress.ip(for: "acme.example.com", lookup: { _ in ["2001:db8::1", "203.0.113.11"] }),
            "203.0.113.11")
        XCTAssertEqual(MoshAddress.ip(for: "acme.example.com", lookup: { _ in ["2001:db8::1"] }), "2001:db8::1")
        XCTAssertNil(MoshAddress.ip(for: "acme.example.com", lookup: { _ in [] }))
    }

    func testTheSystemLookupReturnsNumericAddresses() {
        let found = MoshAddress.systemLookup("localhost")
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.allSatisfy(MoshAddress.isIPAddress))
    }

    func testIPLiterals() {
        XCTAssertTrue(MoshAddress.isIPAddress("100.64.0.5"))
        XCTAssertTrue(MoshAddress.isIPAddress("2001:db8::1"))
        XCTAssertFalse(MoshAddress.isIPAddress("acme.example.com"))
        XCTAssertFalse(MoshAddress.isIPAddress("300.1.1.1"))
    }
}

final class RemoteTransportPolicyTests: XCTestCase {
    private let client = "/opt/homebrew/bin/mosh-client"

    func testAlwaysSSHNeverTriesMosh() {
        XCTAssertEqual(
            RemoteTransportPolicy.plan(mode: .alwaysSSH, remembered: nil, clientPath: client),
            .ssh(reason: nil))
    }

    func testAutomaticTriesMoshWithTheWatchdog() {
        XCTAssertEqual(
            RemoteTransportPolicy.plan(mode: .automatic, remembered: nil, clientPath: client),
            .mosh(client: client, watchdog: true))
    }

    func testAutomaticGoesStraightToSSHForAMachineThatFailedRecently() {
        XCTAssertEqual(
            RemoteTransportPolicy.plan(mode: .automatic, remembered: .udpBlocked, clientPath: client),
            .ssh(reason: .udpBlocked))
    }

    func testAlwaysMoshIgnoresMemoryAndTheWatchdog() {
        XCTAssertEqual(
            RemoteTransportPolicy.plan(mode: .alwaysMosh, remembered: .udpBlocked, clientPath: client),
            .mosh(client: client, watchdog: false))
    }

    func testNoClientMeansSSHWhateverTheMode() {
        XCTAssertEqual(
            RemoteTransportPolicy.plan(mode: .automatic, remembered: nil, clientPath: nil),
            .ssh(reason: .noClient))
        XCTAssertEqual(
            RemoteTransportPolicy.plan(mode: .alwaysMosh, remembered: nil, clientPath: nil),
            .ssh(reason: .noClient))
    }

    func testBootstrapOutcomes() {
        let session = MoshSession(port: 60001, key: "AbCdEfGhIjKlMnOpQrStUv", serverPID: 7)
        XCTAssertNil(RemoteTransportPolicy.fallback(after: .ready(session)))
        XCTAssertEqual(RemoteTransportPolicy.fallback(after: .noServer("x")), .noServer)
        XCTAssertEqual(RemoteTransportPolicy.fallback(after: .serverFailed("x")), .serverFailed)
        XCTAssertEqual(RemoteTransportPolicy.fallback(after: .unreachable("x")), .unreachable)
    }

    func testOnlyAnAnswerAboutTheMachineIsRemembered() {
        XCTAssertTrue(MoshFallbackReason.noServer.isRemembered)
        XCTAssertTrue(MoshFallbackReason.serverFailed.isRemembered)
        XCTAssertTrue(MoshFallbackReason.udpBlocked.isRemembered)
        XCTAssertFalse(MoshFallbackReason.unreachable.isRemembered)
        XCTAssertFalse(MoshFallbackReason.noClient.isRemembered)
        XCTAssertFalse(MoshFallbackReason.noAddress.isRemembered)
    }

    func testOnlyAClosedPathShowsANotice() {
        XCTAssertTrue(MoshFallbackReason.udpBlocked.showsNotice)
        XCTAssertTrue(MoshFallbackReason.clientExited.showsNotice)
        XCTAssertFalse(MoshFallbackReason.noServer.showsNotice)
        XCTAssertFalse(MoshFallbackReason.unreachable.showsNotice)
    }

    func testTheUDPNoticeNamesTheMachineAndThePortRange() {
        XCTAssertEqual(
            MoshFallbackReason.udpBlocked.notice(machine: "main"),
            "Using ssh: mosh couldn't reach main (UDP 60000\u{2013}61000 closed?)")
    }
}

final class RemoteTransportMemoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testAFailureIsRememberedPerMachine() {
        var memory = RemoteTransportMemory()
        memory.record(.udpBlocked, for: "main", at: start)
        XCTAssertEqual(memory.remembered(for: "main", now: start.addingTimeInterval(60)), .udpBlocked)
        XCTAssertNil(memory.remembered(for: "other", now: start))
    }

    func testTheMachineIsProbedAgainAfterThirtyMinutes() {
        var memory = RemoteTransportMemory()
        memory.record(.udpBlocked, for: "main", at: start)
        XCTAssertEqual(memory.remembered(for: "main", now: start.addingTimeInterval(30 * 60 - 1)), .udpBlocked)
        XCTAssertNil(memory.remembered(for: "main", now: start.addingTimeInterval(30 * 60)))
    }

    func testAReasonThatIsNotAboutTheMachineIsNotRemembered() {
        var memory = RemoteTransportMemory()
        memory.record(.unreachable, for: "main", at: start)
        XCTAssertNil(memory.remembered(for: "main", now: start))
    }

    func testAManualRetryForgetsTheMachine() {
        var memory = RemoteTransportMemory()
        memory.record(.noServer, for: "main", at: start)
        memory.forget("main")
        XCTAssertNil(memory.remembered(for: "main", now: start))
    }

    func testAWorkingMoshClearsAnEarlierFailure() {
        var memory = RemoteTransportMemory()
        memory.record(.udpBlocked, for: "main", at: start)
        memory.recordSuccess(for: "main")
        XCTAssertNil(memory.remembered(for: "main", now: start))
    }
}

final class RemoteTerminalModeTests: XCTestCase {
    func testTheDefaultIsAutomatic() {
        XCTAssertEqual(AppSettings.empty.remoteTerminalMode, .automatic)
    }

    func testOldSettingsDecodeToAutomaticAndTheChoiceRoundTrips() throws {
        let old = #"{"opsRepoPath":"","hostAlias":"","publicIP":"","baseDomain":""}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.remoteTerminalMode, .automatic)

        var settings = AppSettings.empty
        settings.remoteTerminalMode = .alwaysSSH
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(again.remoteTerminalMode, .alwaysSSH)
    }

    func testTitles() {
        XCTAssertEqual(RemoteTerminalMode.automatic.title, "Automatic (mosh, falling back to ssh)")
        XCTAssertEqual(RemoteTerminalMode.alwaysSSH.title, "Always ssh")
        XCTAssertEqual(RemoteTerminalMode.alwaysMosh.title, "Always mosh")
    }
}

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    typealias Reply = (stdout: String, stderr: String, exitCode: Int32)
    private let lock = NSLock()
    private let replies: (String, [String]) -> Reply
    private(set) var calls: [[String]] = []

    init(_ replies: @escaping (String, [String]) -> Reply) {
        self.replies = replies
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws -> Reply {
        lock.lock()
        calls.append([executable] + args)
        lock.unlock()
        return replies(executable, args)
    }
}

final class MoshConnectorTests: XCTestCase {
    private let connectLine = "MOSH CONNECT 60001 AbCdEfGhIjKlMnOpQrStUv\n"
    private let detached = "[mosh-server detached, pid = 4242]\n"
    private let resolveJSON = #"{"machine":"main","addresses":[{"address":"100.64.0.5","source":"tailscale:main","package":"tailscale"}],"dropped":[]}"#

    private func connector(_ runner: ScriptedRunner, cli: String? = "/opt/homebrew/bin/devmachine",
                           lookup: @escaping @Sendable (String) -> [String] = { _ in [] }) -> MoshConnector {
        MoshConnector(
            runner: runner, sshEnvironment: [:], cliExecutable: cli, cliEnvironment: [:],
            resolveSupport: ResolveSupport(), lookup: lookup)
    }

    func testUsesTheFirstAddressTheCLIResolves() {
        let runner = ScriptedRunner { exe, args in
            if exe.hasSuffix("/ssh") { return (self.connectLine, self.detached, 0) }
            if args == ["resolve", "--help"] { return ("Usage:\n  devmachine resolve [flags]", "", 0) }
            if args.first == "resolve" { return (self.resolveJSON, "", 0) }
            return ("", "unexpected", 1)
        }
        let result = connector(runner).connect(alias: "acme-devmachine", session: "dev", machine: "main")
        XCTAssertEqual(result, .mosh(
            ip: "100.64.0.5", session: MoshSession(port: 60001, key: "AbCdEfGhIjKlMnOpQrStUv", serverPID: 4242)))
    }

    func testWithoutResolveUsesTheHostSSHConnectsTo() {
        let runner = ScriptedRunner { exe, args in
            if exe.hasSuffix("/ssh"), args.first == "-G" { return ("user alice\nhostname acme.example.com\n", "", 0) }
            if exe.hasSuffix("/ssh") { return (self.connectLine, "", 0) }
            return ("", "Error: unknown command \"resolve\" for \"devmachine\"", 1)
        }
        let result = connector(runner, lookup: { name in
            name == "acme.example.com" ? ["203.0.113.10"] : []
        }).connect(alias: "acme-devmachine", session: "dev", machine: "main")
        XCTAssertEqual(result, .mosh(
            ip: "203.0.113.10", session: MoshSession(port: 60001, key: "AbCdEfGhIjKlMnOpQrStUv", serverPID: nil)))
        XCTAssertTrue(runner.calls.contains(["/usr/bin/ssh", "-G", "acme-devmachine"]))
    }

    func testWithoutAMachineNameTheCLIIsNotAsked() {
        let runner = ScriptedRunner { exe, args in
            if exe.hasSuffix("/ssh"), args.first == "-G" { return ("hostname 203.0.113.10\n", "", 0) }
            if exe.hasSuffix("/ssh") { return (self.connectLine, "", 0) }
            XCTFail("the CLI was asked: \(args)")
            return ("", "", 1)
        }
        let result = connector(runner).connect(alias: "acme-devmachine", session: "dev", machine: nil)
        guard case let .mosh(ip, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(ip, "203.0.113.10")
    }

    func testAMissingServerGoesToSSHWithoutLookingForAnAddress() {
        let runner = ScriptedRunner { _, _ in ("", "bash: line 1: mosh-server: command not found", 127) }
        let result = connector(runner).connect(alias: "acme-devmachine", session: "dev", machine: "main")
        XCTAssertEqual(result, .ssh(
            reason: .noServer, detail: "bash: line 1: mosh-server: command not found", strayServerPID: nil))
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testNoAddressGoesToSSHAndEndsTheServer() {
        let runner = ScriptedRunner { exe, args in
            if exe.hasSuffix("/ssh"), args.first == "-G" { return ("hostname acme.example.com\n", "", 0) }
            if exe.hasSuffix("/ssh") { return (self.connectLine, self.detached, 0) }
            return ("", "", 1)
        }
        let result = connector(runner).connect(alias: "acme-devmachine", session: "dev", machine: "main")
        guard case let .ssh(reason, _, pid) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(reason, .noAddress)
        XCTAssertEqual(pid, 4242)
    }

    func testTheCLIHelpIsReadOncePerAppSession() {
        let support = ResolveSupport()
        let runner = ScriptedRunner { exe, args in
            if exe.hasSuffix("/ssh") { return (self.connectLine, "", 0) }
            if args == ["resolve", "--help"] { return ("devmachine resolve", "", 0) }
            return (self.resolveJSON, "", 0)
        }
        let connector = MoshConnector(
            runner: runner, sshEnvironment: [:], cliExecutable: "/opt/homebrew/bin/devmachine",
            cliEnvironment: [:], resolveSupport: support, lookup: { _ in [] })
        _ = connector.connect(alias: "acme-devmachine", session: "a", machine: "main")
        _ = connector.connect(alias: "acme-devmachine", session: "b", machine: "main")
        XCTAssertEqual(runner.calls.filter { $0.last == "--help" }.count, 1)
    }
}
