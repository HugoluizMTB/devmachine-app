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
        super.tearDown()
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
}
