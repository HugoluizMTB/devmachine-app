import XCTest
import DevmachineCore
@testable import DevmachineApp

private let detectedFixture = CLIDetectedSettings(
    opsRepoPath: "/Users/alice/.config/devmachine", adminMachine: "acme",
    publicIP: "203.0.113.10", baseDomain: "example.com",
    workspaceAliases: ["acme": "acme-devmachine"])

@MainActor
final class CLIGateTests: XCTestCase {
    private let workspace = Workspace(name: "acme", alias: "acme-devmachine")

    private func model(
        cliFound: @escaping @Sendable () -> Bool,
        detected: CLIDetectedSettings = .empty,
        defaults: UserDefaults = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
    ) -> AppModel {
        AppModel(
            store: SessionStore(runner: NeverCalledRunner()),
            services: fixtureServices(workspaces: [workspace]),
            cliAvailabilityCheck: cliFound,
            detectSettings: { detected },
            defaults: defaults)
    }

    func testMissingCLIShowsOnboardingAndStartsNothing() {
        let model = model(cliFound: { false })

        model.checkCLIAndProceed(isConfigured: false)

        XCTAssertTrue(model.cliMissing)
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertNil(model.activePage)
        XCTAssertTrue(model.workspaces.isEmpty)
    }

    func testAnUnconfiguredAppGoesToOnboardingNeverToSettings() {
        let model = model(cliFound: { true })

        model.checkCLIAndProceed(isConfigured: false)

        XCTAssertFalse(model.cliMissing)
        XCTAssertTrue(model.showsOnboarding)
        XCTAssertNotEqual(model.activePage, .setup)
    }

    func testAConfiguredAppWithTheCLILoadsWorkspaces() {
        let model = model(cliFound: { true })
        model.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev", hostAlias: "lab", publicIP: "203.0.113.10", baseDomain: "example.com")

        model.checkCLIAndProceed(isConfigured: true)

        XCTAssertFalse(model.showsOnboarding)
        XCTAssertNil(model.activePage)
        XCTAssertEqual(model.workspaces, [workspace])
    }

    func testLaunchRoute() {
        XCTAssertEqual(AppModel.launchRoute(cliFound: false, isConfigured: false, skipped: false), .onboarding)
        XCTAssertEqual(AppModel.launchRoute(cliFound: false, isConfigured: true, skipped: false), .onboarding)
        XCTAssertEqual(AppModel.launchRoute(cliFound: true, isConfigured: false, skipped: false), .onboarding)
        XCTAssertEqual(AppModel.launchRoute(cliFound: true, isConfigured: true, skipped: false), .home)
        XCTAssertEqual(AppModel.launchRoute(cliFound: false, isConfigured: true, skipped: true), .home)
        XCTAssertEqual(AppModel.launchRoute(cliFound: false, isConfigured: false, skipped: true), .onboarding)
    }

    func testStartUsingSavesWhatTheCLIReportsAndOpensHome() async {
        let suite = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        let model = model(cliFound: { true }, detected: detectedFixture)
        model.checkCLIAndProceed(isConfigured: store.isConfigured)
        XCTAssertTrue(model.showsOnboarding)

        await model.completeOnboarding(saving: store)

        XCTAssertFalse(model.showsOnboarding)
        XCTAssertNil(model.activePage, "never lands on Settings")
        XCTAssertEqual(store.settings?.opsRepoPath, "/Users/alice/.config/devmachine")
        XCTAssertEqual(store.settings?.publicIP, "203.0.113.10")
        XCTAssertEqual(store.settings?.baseDomain, "example.com")
        XCTAssertEqual(model.settings, store.settings)
        XCTAssertEqual(model.detected, detectedFixture)
        XCTAssertEqual(model.workspaces, [workspace])
        XCTAssertEqual(SettingsStore(defaults: suite).settings, store.settings, "saved, not only in memory")
    }

    func testStartUsingKeepsValuesTheUserAlreadySaved() async {
        let suite = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        var saved = AppSettings.empty
        saved.baseDomain = "example.net"
        saved.terminalFontSize = 15
        store.settings = saved
        let model = model(cliFound: { true }, detected: detectedFixture)

        await model.completeOnboarding(saving: store)

        XCTAssertEqual(store.settings?.baseDomain, "example.net")
        XCTAssertEqual(store.settings?.terminalFontSize, 15)
        XCTAssertEqual(store.settings?.opsRepoPath, "/Users/alice/.config/devmachine")
    }

    func testSkipOpensHomeAndIsRememberedForTheNextLaunch() async {
        let suite = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        let first = model(cliFound: { false }, defaults: suite)
        first.checkCLIAndProceed(isConfigured: store.isConfigured)
        XCTAssertTrue(first.showsOnboarding)

        await first.skipOnboarding(saving: store)

        XCTAssertFalse(first.showsOnboarding)
        XCTAssertNil(first.activePage)
        XCTAssertTrue(store.isConfigured)
        XCTAssertTrue(first.hasLoadedWorkspaces)

        let next = model(cliFound: { false }, defaults: suite)
        next.settings = store.settings
        next.checkCLIAndProceed(isConfigured: store.isConfigured)
        XCTAssertFalse(next.showsOnboarding)
    }

    func testOpeningTheSetupAgainShowsOnboardingAndForgetsTheSkip() async {
        let suite = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        let model = model(cliFound: { false }, defaults: suite)
        await model.skipOnboarding(saving: store)
        model.activePage = .setup

        model.openOnboarding()

        XCTAssertTrue(model.showsOnboarding)
        XCTAssertNil(model.activePage)
        XCTAssertFalse(model.onboardingSkipped)
    }

    func testDetectionIsReadAgainOnRequest() async {
        let model = model(cliFound: { true }, detected: detectedFixture)
        XCTAssertEqual(model.detected, .empty)

        let detected = await model.refreshDetected()

        XCTAssertEqual(detected, detectedFixture)
        XCTAssertEqual(model.detected, detectedFixture)
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
