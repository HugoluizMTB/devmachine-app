import XCTest
@testable import DevmachineCore

final class UpdatePreferencesTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "app.devmachine.mac.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testAutomaticChecksAreOnUntilTurnedOff() {
        let preferences = UpdatePreferences(defaults: defaults)
        XCTAssertTrue(preferences.automaticChecks)
        preferences.automaticChecks = false
        XCTAssertFalse(UpdatePreferences(defaults: defaults).automaticChecks)
    }

    func testRemembersTheSkippedVersion() {
        let preferences = UpdatePreferences(defaults: defaults)
        XCTAssertNil(preferences.skippedVersion)
        preferences.skippedVersion = "0.1.3"
        XCTAssertEqual(UpdatePreferences(defaults: defaults).skippedVersion, "0.1.3")
        preferences.skippedVersion = nil
        XCTAssertNil(UpdatePreferences(defaults: defaults).skippedVersion)
    }

    func testRemembersTheCLIVersionPutOffWithLater() {
        let preferences = UpdatePreferences(defaults: defaults)
        XCTAssertNil(preferences.cliLaterVersion)
        preferences.cliLaterVersion = "0.8.0"
        XCTAssertEqual(UpdatePreferences(defaults: defaults).cliLaterVersion, "0.8.0")
        XCTAssertNil(preferences.skippedVersion)
    }

    func testRemembersThePackagesReleasePutOffWithLater() {
        let preferences = UpdatePreferences(defaults: defaults)
        XCTAssertNil(preferences.packagesLaterVersion)
        preferences.packagesLaterVersion = "v33"
        XCTAssertEqual(UpdatePreferences(defaults: defaults).packagesLaterVersion, "v33")
        XCTAssertNil(preferences.cliLaterVersion)
    }

    func testPreferencesSavedBeforeThePackagesCardStillRead() {
        defaults.set("0.8.0", forKey: "updates.cliLaterVersion")
        defaults.set(33, forKey: "updates.packagesLaterVersion")
        let preferences = UpdatePreferences(defaults: defaults)
        XCTAssertEqual(preferences.cliLaterVersion, "0.8.0")
        XCTAssertEqual(preferences.packagesLaterVersion, "33")
    }

    func testKeepsOneCachedAnswerPerFeed() {
        let preferences = UpdatePreferences(defaults: defaults)
        let app = CachedRelease(etag: "\"a\"", body: Data("{}".utf8))
        preferences.setCache(app, for: ReleaseFeed.appReleases)
        XCTAssertEqual(UpdatePreferences(defaults: defaults).cache(for: ReleaseFeed.appReleases), app)
        XCTAssertNil(preferences.cache(for: ReleaseFeed.cliReleases))
    }
}
