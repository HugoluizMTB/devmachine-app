import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedHTTP: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [URL: [HTTPResponse]] = [:]
    private(set) var requested: [URL] = []

    func queue(_ url: URL, _ response: HTTPResponse) {
        lock.lock()
        answers[url, default: []].append(response)
        lock.unlock()
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let next: HTTPResponse? = lock.withLock {
            requested.append(url)
            guard var list = answers[url], !list.isEmpty else { return nil }
            let next = list.removeFirst()
            answers[url] = list
            return next
        }
        guard let next else { throw URLError(.notConnectedToInternet) }
        return next
    }
}

private final class FakeInstaller: AppUpdateInstalling, @unchecked Sendable {
    var outcome: Result<ManualInstallOutcome, Error> = .success(.replaced(URL(fileURLWithPath: "/Applications/Devmachine.app")))
    private(set) var installed: [String] = []

    func install(
        release: GitHubRelease, progress: @escaping @Sendable (UpdateProgress) -> Void
    ) async throws -> ManualInstallOutcome {
        installed.append(release.tagName)
        progress(.downloading(0.5))
        return try outcome.get()
    }
}

private final class FakeHomebrew: HomebrewUpgrading, @unchecked Sendable {
    var exitCode: Int32 = 0
    private(set) var runs: [String] = []

    func upgrade(brew: String, output: @escaping @Sendable (String) -> Void) async throws {
        runs.append(brew)
        output("==> Upgrading devmachine-app")
        if exitCode != 0 { throw UpdateInstallError.homebrewFailed(exitCode) }
    }
}

private struct Boom: Error {}

private func releaseJSON(_ tag: String) -> Data {
    Data(#"{"tag_name":"\#(tag)","body":"Faster start.\n\nsha256: \#(String(repeating: "a", count: 64))","html_url":"https://example.com/r/\#(tag)"}"#.utf8)
}

@MainActor
final class UpdateControllerTests: XCTestCase {
    private var suite: String!
    private var preferences: UpdatePreferences!
    private var http: ScriptedHTTP!
    private var installer: FakeInstaller!
    private var homebrew: FakeHomebrew!
    private var relaunched: [URL] = []
    private var cliOutput: String? = "0.7.1"

    override func setUp() async throws {
        suite = "app.devmachine.mac.tests.\(UUID().uuidString)"
        preferences = UpdatePreferences(defaults: UserDefaults(suiteName: suite)!)
        http = ScriptedHTTP()
        installer = FakeInstaller()
        homebrew = FakeHomebrew()
        relaunched = []
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func controller(
        method: AppInstallMethod = .manual, runningTeam: String? = "TEAM123456", current: String? = "0.1.2",
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in throw CancellationError() }
    ) -> UpdateController {
        let cliOutput = cliOutput
        return UpdateController(dependencies: UpdateDependencies(
            currentVersion: current.flatMap { SemanticVersion($0) },
            appFeed: ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: http, userAgent: "Devmachine"),
            cliFeed: ReleaseFeed(url: ReleaseFeed.cliReleases, fetcher: http, userAgent: "Devmachine"),
            preferences: preferences,
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            sleep: sleep,
            detectInstallMethod: { method },
            runningTeamID: runningTeam,
            cliVersion: { cliOutput.map { CLIVersionReading(output: $0, method: .homebrew) } },
            installer: installer,
            homebrew: homebrew,
            currentAppURL: URL(fileURLWithPath: "/Applications/Devmachine.app"),
            relaunch: { [weak self] url in self?.relaunched.append(url) }))
    }

    private func serve(app tag: String, cli cliTag: String = "v0.7.1") {
        http.queue(ReleaseFeed.appReleases, HTTPResponse(status: 200, headers: ["ETag": "\"e\""], body: releaseJSON(tag)))
        http.queue(ReleaseFeed.cliReleases, HTTPResponse(status: 200, headers: [:], body: releaseJSON(cliTag)))
    }

    func testANewerReleaseShowsTheBanner() async {
        serve(app: "v0.1.3")
        let updates = controller()

        await updates.check(userInitiated: false)

        XCTAssertEqual(updates.availableRelease?.tagName, "v0.1.3")
        XCTAssertTrue(updates.showsBanner)
        XCTAssertEqual(updates.releaseNotes, "Faster start.")
        XCTAssertEqual(preferences.cache(for: ReleaseFeed.appReleases)?.etag, "\"e\"")
    }

    func testTheSameVersionIsUpToDate() async {
        serve(app: "v0.1.2")
        let updates = controller()
        await updates.check(userInitiated: true)
        XCTAssertEqual(updates.availability, .upToDate)
        XCTAssertFalse(updates.showsBanner)
        XCTAssertNotNil(updates.lastCheckedAt)
    }

    func testSkippingHidesTheBannerAndIsRemembered() async {
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)

        updates.skipThisVersion()

        XCTAssertFalse(updates.showsBanner)
        XCTAssertEqual(preferences.skippedVersion, "0.1.3")
        serve(app: "v0.1.3")
        await updates.check(userInitiated: false)
        XCTAssertFalse(updates.showsBanner)
        XCTAssertEqual(updates.availableRelease?.tagName, "v0.1.3")
    }

    func testANewerVersionThanTheSkippedOneShowsAgain() async {
        preferences.skippedVersion = "0.1.3"
        serve(app: "v0.1.4")
        let updates = controller()
        await updates.check(userInitiated: false)
        XCTAssertTrue(updates.showsBanner)
    }

    func testLaterHidesTheBannerUntilAnotherVersionAppears() async {
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)
        updates.later()
        XCTAssertFalse(updates.showsBanner)

        serve(app: "v0.1.3")
        await updates.check(userInitiated: false)
        XCTAssertFalse(updates.showsBanner)

        serve(app: "v0.1.4")
        await updates.check(userInitiated: false)
        XCTAssertTrue(updates.showsBanner)
    }

    func testAFailedCheckKeepsTheErrorForSettings() async {
        let updates = controller()
        await updates.check(userInitiated: true)
        XCTAssertNotNil(updates.checkError)
        XCTAssertFalse(updates.showsBanner)
    }

    func testANewerCLIReleaseMakesTheNotice() async {
        serve(app: "v0.1.2", cli: "v0.8.0")
        let updates = controller()
        await updates.check(userInitiated: false)
        XCTAssertEqual(updates.cliNotice?.latest, SemanticVersion("0.8.0"))
        XCTAssertEqual(updates.cliNotice?.command, "brew upgrade devmachine")
    }

    func testNoCLIMeansNoNotice() async {
        cliOutput = nil
        serve(app: "v0.1.2", cli: "v0.8.0")
        let updates = controller()
        await updates.check(userInitiated: false)
        XCTAssertNil(updates.cliNotice)
    }

    func testAManualInstallRelaunchesTheReplacedApp() async {
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)

        await updates.install()

        XCTAssertEqual(installer.installed, ["v0.1.3"])
        XCTAssertEqual(relaunched, [URL(fileURLWithPath: "/Applications/Devmachine.app")])
        XCTAssertEqual(updates.phase, .relaunching)
    }

    func testAFolderItCannotWriteAsksToMoveTheAppByHand() async {
        let staged = URL(fileURLWithPath: "/tmp/devmachine-update/Devmachine.app")
        installer.outcome = .success(.needsManualMove(staged))
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)

        await updates.install()

        XCTAssertEqual(updates.phase, .manualMove(staged))
        XCTAssertTrue(relaunched.isEmpty)
    }

    func testAFailedInstallShowsTheErrorAndDoesNotRelaunch() async {
        installer.outcome = .failure(UpdateInstallError.teamMismatch(expected: "TEAM123456", found: "OTHER99999"))
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)

        await updates.install()

        guard case .failed(let state) = updates.phase else { return XCTFail("\(updates.phase)") }
        XCTAssertTrue(state.details.contains("OTHER99999"))
        XCTAssertTrue(relaunched.isEmpty)
    }

    func testAHomebrewInstallRunsBrewAndRelaunches() async {
        serve(app: "v0.1.3")
        let updates = controller(method: .homebrew(brew: "/opt/homebrew/bin/brew"))
        await updates.check(userInitiated: false)

        await updates.install()

        XCTAssertEqual(homebrew.runs, ["/opt/homebrew/bin/brew"])
        XCTAssertTrue(installer.installed.isEmpty)
        XCTAssertEqual(updates.homebrewOutput, ["==> Upgrading devmachine-app"])
        XCTAssertEqual(relaunched, [URL(fileURLWithPath: "/Applications/Devmachine.app")])
    }

    func testAFailedBrewKeepsItsOutputInTheError() async {
        homebrew.exitCode = 1
        serve(app: "v0.1.3")
        let updates = controller(method: .homebrew(brew: "/opt/homebrew/bin/brew"))
        await updates.check(userInitiated: false)

        await updates.install()

        guard case .failed(let state) = updates.phase else { return XCTFail("\(updates.phase)") }
        XCTAssertTrue(state.details.contains("==> Upgrading devmachine-app"))
        XCTAssertTrue(relaunched.isEmpty)
    }

    func testAnUnsignedLocalBuildCannotInstallInPlace() async {
        serve(app: "v0.1.3")
        let updates = controller(runningTeam: nil)
        await updates.check(userInitiated: false)
        XCTAssertFalse(updates.canInstallInPlace)

        serve(app: "v0.1.3")
        let brewed = controller(method: .homebrew(brew: "/opt/homebrew/bin/brew"), runningTeam: nil)
        await brewed.check(userInitiated: false)
        XCTAssertTrue(brewed.canInstallInPlace)
    }

    func testWithoutABundleVersionNothingIsChecked() async {
        let updates = controller(current: nil)
        await updates.check(userInitiated: true)
        XCTAssertTrue(http.requested.isEmpty)
        XCTAssertNil(updates.availability)
    }

    func testTurningAutomaticChecksOffIsSaved() {
        let updates = controller()
        updates.automaticChecks = false
        XCTAssertFalse(preferences.automaticChecks)
    }

    func testTheLoopChecksThirtySecondsAfterLaunchThenEverySixHours() async {
        serve(app: "v0.1.3")
        let sleeps = SleepRecorder(allowed: 2)
        let updates = controller(sleep: { try await sleeps.sleep($0) })

        await updates.runSchedule()

        XCTAssertEqual(sleeps.delays, [30, 21_600, 21_600])
        XCTAssertEqual(http.requested.filter { $0 == ReleaseFeed.appReleases }.count, 2)
    }

    func testTheLoopDoesNotCheckWhileAutomaticChecksAreOff() async {
        preferences.automaticChecks = false
        let sleeps = SleepRecorder(allowed: 1)
        let updates = controller(sleep: { try await sleeps.sleep($0) })

        await updates.runSchedule()

        XCTAssertTrue(http.requested.isEmpty)
        XCTAssertEqual(sleeps.delays.count, 2)
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []
    private let allowed: Int

    init(allowed: Int) {
        self.allowed = allowed
    }

    var delays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func sleep(_ delay: TimeInterval) async throws {
        let count = lock.withLock {
            recorded.append(delay)
            return recorded.count
        }
        if count > allowed { throw CancellationError() }
    }
}
