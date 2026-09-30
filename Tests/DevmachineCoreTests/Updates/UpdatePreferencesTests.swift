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

    func testKeepsOneCachedAnswerPerFeed() {
        let preferences = UpdatePreferences(defaults: defaults)
        let app = CachedRelease(etag: "\"a\"", body: Data("{}".utf8))
        preferences.setCache(app, for: ReleaseFeed.appReleases)
        XCTAssertEqual(UpdatePreferences(defaults: defaults).cache(for: ReleaseFeed.appReleases), app)
        XCTAssertNil(preferences.cache(for: ReleaseFeed.cliReleases))
    }
}
