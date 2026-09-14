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
        baseDomain: "example.com"
    )

    func testStartsUnconfigured() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.settings)
        XCTAssertFalse(store.isConfigured)
    }

    func testSavedSettingsComeBackOnTheNextLaunch() {
        SettingsStore(defaults: defaults).settings = sample

        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.settings, sample)
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
