import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class SettingsStoreTests: XCTestCase {
    private let suiteName = "dev.devmachine.app.settings.tests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        RemoteCommands.SSHAgentSocketPreference.shared.update(nil)
        DMFont.scale = 1
        super.tearDown()
    }

    func testTheAppsStoreSetsTheTextSizeBeforeTheNextRender() {
        let store = SettingsStore(defaults: defaults, drivesTextSize: true)
        var settings = sample
        settings.uiFontScale = 1.4
        store.settings = settings
        XCTAssertEqual(DMFont.scale, 1.4)
        XCTAssertEqual(DMMetrics.current, DMMetrics(scale: 1.4))
    }

    func testAnyOtherStoreLeavesTheTextSizeAlone() {
        let store = SettingsStore(defaults: defaults)
        var settings = sample
        settings.uiFontScale = 1.4
        store.settings = settings
        XCTAssertEqual(DMFont.scale, 1)
    }

    func testTheSavedTextSizeIsUsedWhileNothingIsPreviewed() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.effectiveUIFontScale, Appearance.defaultUIFontScale)
        var settings = sample
        settings.uiFontScale = 1.2
        store.settings = settings
        XCTAssertNil(store.previewUIFontScale)
        XCTAssertEqual(store.effectiveUIFontScale, 1.2)
    }

    func testAPreviewedTextSizeWinsOverTheSavedOne() {
        let store = SettingsStore(defaults: defaults, drivesTextSize: true)
        var settings = sample
        settings.uiFontScale = 1.2
        store.settings = settings
        store.preview(uiFontScale: 1.4)
        XCTAssertEqual(store.effectiveUIFontScale, 1.4)
        XCTAssertEqual(DMFont.scale, 1.4)
        XCTAssertEqual(store.settings?.uiFontScale, 1.2)
    }

    func testAPreviewMovesInSliderSteps() throws {
        let store = SettingsStore(defaults: defaults)
        store.preview(uiFontScale: 1.23)
        XCTAssertEqual(try XCTUnwrap(store.previewUIFontScale), 1.25, accuracy: 0.0001)
        store.preview(uiFontScale: 9)
        XCTAssertEqual(store.previewUIFontScale, Appearance.uiFontScaleRange.upperBound)
    }

    func testCommitKeepsThePreviewedSizeAndEndsThePreview() {
        let store = SettingsStore(defaults: defaults, drivesTextSize: true)
        store.settings = sample
        store.preview(uiFontScale: 1.5)
        var draft = store.draft()
        draft.value.uiFontScale = 1.5
        store.commit(draft)
        XCTAssertNil(store.previewUIFontScale)
        XCTAssertEqual(store.effectiveUIFontScale, 1.5)
        XCTAssertEqual(DMFont.scale, 1.5)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings?.uiFontScale, 1.5)
    }

    func testLeavingSettingsPutsTheSavedSizeBack() {
        let store = SettingsStore(defaults: defaults, drivesTextSize: true)
        var settings = sample
        settings.uiFontScale = 1.1
        store.settings = settings
        store.preview(uiFontScale: 1.5)
        store.leaveSettingsPage()
        XCTAssertNil(store.previewUIFontScale)
        XCTAssertEqual(store.effectiveUIFontScale, 1.1)
        XCTAssertEqual(DMFont.scale, 1.1)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings?.uiFontScale, 1.1)
    }

    func testAnEditOnTheSettingsPageSurvivesAPreview() {
        let store = SettingsStore(defaults: defaults)
        let page = store.settingsPageDraft(initialSection: .appearance)
        page.hostAlias = "edited-host"
        page.uiFontScale = 1.3
        store.preview(uiFontScale: 1.3)
        let after = store.settingsPageDraft(initialSection: .general)
        XCTAssertTrue(after === page)
        XCTAssertEqual(after.hostAlias, "edited-host")
        XCTAssertEqual(after.section, .appearance)
    }

    func testLeavingSettingsStartsTheNextVisitFromAFreshPage() {
        let store = SettingsStore(defaults: defaults)
        let page = store.settingsPageDraft(initialSection: .appearance)
        page.hostAlias = "edited-host"
        page.isLoaded = true
        store.leaveSettingsPage()
        let next = store.settingsPageDraft(initialSection: .general)
        XCTAssertFalse(next === page)
        XCTAssertEqual(next.hostAlias, "")
        XCTAssertFalse(next.isLoaded)
        XCTAssertEqual(next.section, .general)
    }

    private let sample = AppSettings(
        opsRepoPath: "/Users/alice/dev/ops",
        hostAlias: "myhost",
        publicIP: "203.0.113.10",
        baseDomain: "example.com",
        enabledHarnesses: [.claude, .codex],
        localSessionProgram: .harness(.codex),
        remoteSessionProgram: .harness(.claude),
        workspaceSessionPrograms: ["acme-devmachine": .harness(.codex)]
    )

    func testStartsUnconfigured() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.settings)
        XCTAssertFalse(store.isConfigured)
    }

    func testDraftCommitPreservesHarnessChoicesOnTheNextLaunch() {
        let store = SettingsStore(defaults: defaults)
        var draft = store.draft()
        draft.value = sample
        store.commit(draft)

        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.draft().value, sample)
        XCTAssertTrue(reopened.isConfigured)
    }

    func testClearingSettingsRemovesThemFromDefaults() {
        let store = SettingsStore(defaults: defaults)
        store.settings = sample
        store.settings = nil

        XCTAssertNil(defaults.data(forKey: "appSettings"))
        XCTAssertNil(SettingsStore(defaults: defaults).settings)
    }

    func testCommittingSettingsUpdatesTheSharedSSHAgentSocketPreferenceAtOnce() {
        var withSocket = sample
        withSocket.sshAgentSocket = "/tmp/custom.sock"
        let store = SettingsStore(defaults: defaults)

        store.settings = withSocket

        XCTAssertEqual(RemoteCommands.SSHAgentSocketPreference.shared.current(), "/tmp/custom.sock")
    }

    func testClearingSettingsClearsTheSharedSSHAgentSocketPreferenceToo() {
        var withSocket = sample
        withSocket.sshAgentSocket = "/tmp/custom.sock"
        let store = SettingsStore(defaults: defaults)
        store.settings = withSocket

        store.settings = nil

        XCTAssertNil(RemoteCommands.SSHAgentSocketPreference.shared.current())
    }

    func testLoadingAnExistingSocketPreferenceOnLaunchSyncsItAtOnce() {
        var withSocket = sample
        withSocket.sshAgentSocket = "/tmp/custom.sock"
        SettingsStore(defaults: defaults).settings = withSocket
        RemoteCommands.SSHAgentSocketPreference.shared.update(nil)

        _ = SettingsStore(defaults: defaults)

        XCTAssertEqual(RemoteCommands.SSHAgentSocketPreference.shared.current(), "/tmp/custom.sock")
    }
}
