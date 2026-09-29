import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class CLIGateTests: XCTestCase {
    private let workspace = Workspace(name: "acme", alias: "acme-devmachine")

    func testMissingCLIActivatesTheGateAndSkipsSetup() {
        let model = AppModel(
            store: SessionStore(runner: NeverCalledRunner()),
            services: fixtureServices(workspaces: [workspace]),
            cliAvailabilityCheck: { false })

        model.checkCLIAndProceed(isConfigured: false)

        XCTAssertTrue(model.cliMissing)
        // The gate owns the window instead: Setup never runs while the CLI
        // is missing, and nothing sweeps the workspaces either.
        XCTAssertNil(model.activePage)
        XCTAssertTrue(model.workspaces.isEmpty)
    }

    func testFoundCLILeavesNoGateAndFallsThroughToSetupWhenUnconfigured() {
        let model = AppModel(
            store: SessionStore(runner: NeverCalledRunner()),
            services: fixtureServices(workspaces: [workspace]),
            cliAvailabilityCheck: { true })

        model.checkCLIAndProceed(isConfigured: false)

        XCTAssertFalse(model.cliMissing)
        XCTAssertEqual(model.activePage, .setup)
    }

    func testCheckAgainClearsTheGateAndFallsThroughToSetupWhenUnconfigured() {
        let cliInstalled = ToggleFlag()
        let model = AppModel(
            store: SessionStore(runner: NeverCalledRunner()),
            services: fixtureServices(workspaces: [workspace]),
            cliAvailabilityCheck: { cliInstalled.value })

        model.checkCLIAndProceed(isConfigured: false)
        XCTAssertTrue(model.cliMissing)
        XCTAssertNil(model.activePage)

        // The user installed it and pressed "Check again".
        cliInstalled.value = true
        model.checkCLIAndProceed(isConfigured: false)

        XCTAssertFalse(model.cliMissing)
        XCTAssertEqual(model.activePage, .setup)
    }

    func testCheckAgainWithConfiguredSettingsLoadsWorkspacesInsteadOfSetup() {
        let model = AppModel(
            store: SessionStore(runner: NeverCalledRunner()),
            services: fixtureServices(workspaces: [workspace]),
            cliAvailabilityCheck: { true })
        model.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev", hostAlias: "lab", publicIP: "203.0.113.10", baseDomain: "example.com")

        model.checkCLIAndProceed(isConfigured: true)

        XCTAssertFalse(model.cliMissing)
        XCTAssertNil(model.activePage)
        XCTAssertEqual(model.workspaces, [workspace])
    }
}

/// Session polling, PR/stats/context lookups: none of them may run while the
/// gate is up. Any call here fails the test that exercises the missing-CLI
/// path.
private final class NeverCalledRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        XCTFail("no command should run while the devmachine CLI gate is active: \(executable) \(args)")
        return ""
    }
}

private final class ToggleFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool

    init(_ value: Bool = false) { stored = value }

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
