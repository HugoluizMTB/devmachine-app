import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Fails the test the moment anything calls it — proves demo mode never
/// reaches a real `CommandRunner`, instead of only checking the values it
/// seeds.
private final class FailingCommandRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        XCTFail("demo mode invoked a real command runner: \(executable) \(args.joined(separator: " "))")
        throw DemoModeError.commandRunnerInvoked(executable: executable)
    }
}

@MainActor
final class DemoModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("DEVMACHINE_DEMO", "1", 1)
    }

    override func tearDown() {
        unsetenv("DEVMACHINE_DEMO")
        super.tearDown()
    }

    func testIsActiveReadsTheEnvironmentVariable() {
        XCTAssertTrue(DemoMode.isActive)
        unsetenv("DEVMACHINE_DEMO")
        XCTAssertFalse(DemoMode.isActive)
    }

    func testDemoCommandRunnerThrowsInsteadOfRunning() {
        let runner = DemoCommandRunner()
        XCTAssertThrowsError(try runner.run(executable: "/usr/bin/ssh", args: [], environment: nil))
    }

    /// `checkCLIAndProceed` is the app's single entry point at launch. In
    /// demo mode it must seed the sidebar from `DemoData` without ever
    /// touching the CLI, ssh, or the injected runners — proven here by
    /// handing it runners that fail the test if called at all.
    func testCheckCLIAndProceedNeverCallsTheRealCommandRunner() {
        let model = AppModel(
            localRunner: FailingCommandRunner(),
            sessionCommandSender: FailingSessionCommandSender(),
            cliAvailabilityCheck: {
                XCTFail("demo mode must not check for the CLI binary")
                return false
            })

        model.checkCLIAndProceed(isConfigured: false)

        XCTAssertEqual(model.workspaces, DemoData.workspaces)
        XCTAssertFalse(model.cliMissing)
        XCTAssertNil(model.activePage)
    }

    func testDemoWorkspacesAndSessionsAreInternallyConsistent() {
        for workspace in DemoData.workspaces {
            XCTAssertFalse(workspace.isLocal)
        }
        for (alias, sessions) in DemoData.sessionsByAlias {
            XCTAssertTrue(DemoData.workspaces.contains { $0.alias == alias },
                          "sessionsByAlias has sessions for an alias not in DemoData.workspaces: \(alias)")
            XCTAssertFalse(sessions.isEmpty)
        }
    }

    func testTerminalTranscriptIsNeverEmpty() {
        let kinds: [TerminalKind] = [
            .remote(alias: "acme-devmachine", session: "claude"),
            .remote(alias: "acme-devmachine", session: "web — landing page"),
            .local(session: "codex", path: "/Users/alice/dev/acme-app"),
            .remote(alias: "unknown", session: "something else entirely"),
        ]
        for kind in kinds {
            XCTAssertFalse(DemoData.terminalTranscript(for: kind).isEmpty)
        }
    }

    /// `PRStore`'s normal `init` calls `refresh()` at once, which would
    /// shell out to `gh` through `GHClient`. In demo mode it must seed
    /// `forest` from `DemoData` instead — proven by handing it a client
    /// backed by a runner that fails the test if invoked.
    func testPRStoreSeedsDemoDataWithoutCallingGH() {
        let store = PRStore(client: GHClient(runner: FailingCommandRunner()))
        XCTAssertEqual(store.openCount, DemoData.pullRequests.count)
        XCTAssertFalse(store.forest.isEmpty)
    }

    func testCaddyStoreRefreshSeedsDemoDataDirectly() {
        let store = CaddyStore()
        store.refresh()
        XCTAssertEqual(store.rows, DemoData.subdomainRows)
        XCTAssertEqual(store.domain, DemoData.domain)
        XCTAssertEqual(store.selectedMachine, "main")
        XCTAssertTrue(store.showsMachinePicker)
        XCTAssertEqual(store.sitesByMachine["staging"]?.rows, DemoData.stagingSubdomainRows)
        XCTAssertNotNil(store.sitesByMachine["laptop"]?.notSetUpMessage)
    }

    func testHealthCheckStoreRunSeedsDemoData() {
        let store = HealthCheckStore()
        store.run()
        XCTAssertEqual(store.results, DemoData.machineHealth)
    }

    func testStatsStoreLoadMachinesSeedsDemoData() {
        let store = StatsStore(cache: nil, tickInterval: nil)
        store.start()
        XCTAssertEqual(store.machines, DemoData.statsMachines)
        XCTAssertEqual(store.selectedMachine, "main")
        XCTAssertEqual(store.snapshot, DemoData.statsSnapshots["main"])
    }

    func testSettingsStoreSeedsDemoSettingsWithoutPersistingThem() {
        let suiteName = "\(#function)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)

        store.settings?.terminalOpacity = 1

        XCTAssertEqual(store.settings?.baseDomain, DemoData.settings.baseDomain)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
    }

    func testDemoSettingsShowACustomSessionDefaultThatIsAlsoASavedCommand() {
        guard case let .custom(command) = DemoData.settings.sessionProgram(for: "globex-devmachine") else {
            return XCTFail("globex should start with a custom command in the demo")
        }
        XCTAssertEqual(DemoData.recentCommands["globex-devmachine"]?.contains(command), true)
    }

    func testRecentCommandStoreSeedsDemoCommandsWithoutPersistingThem() {
        let suiteName = "\(#function)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = RecentCommandStore(defaults: defaults)

        store.record("make test", for: "acme-devmachine")

        XCTAssertEqual(
            store.recents(for: "globex-devmachine"),
            DemoData.recentCommands["globex-devmachine"])
        XCTAssertEqual(store.recents(for: "acme-devmachine").first, "make test")
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
    }
}

private final class FailingSessionCommandSender: SessionCommandSending, @unchecked Sendable {
    func send(_ command: String, into target: CommandTarget) throws {
        XCTFail("demo mode must not send a command into a real session")
    }
}
