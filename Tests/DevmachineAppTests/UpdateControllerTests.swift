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

private final class VersionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ value: String?) { stored = value }
    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class FakeCLIUpdater: CLIUpdating, @unchecked Sendable {
    var lines = ["==> CLI", "  0.7.23 → v0.8.0", "  upgrading through Homebrew", "  updated: 0.7.23 → 0.8.0"]
    var failure: Error?
    var installs: String? = "0.8.0"
    var stdout = Data()
    let version: VersionBox
    private(set) var commands: [CLIUpdateCommand] = []
    var runs: Int { commands.count }

    init(version: VersionBox) { self.version = version }

    func run(_ command: CLIUpdateCommand, output: @escaping @Sendable (String) -> Void) async throws -> Data {
        commands.append(command)
        lines.forEach(output)
        if let failure { throw failure }
        if command != .packagesOnly { version.value = installs }
        return stdout
    }
}

private final class FakeOutdated: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Result<String, Error> = .failure(Boom())
    private(set) var reads = 0

    func answer(_ json: String) { lock.withLock { answer = .success(json) } }
    func fail() { lock.withLock { answer = .failure(Boom()) } }

    func read() throws -> Data {
        let answer = lock.withLock {
            reads += 1
            return self.answer
        }
        return Data(try answer.get().utf8)
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
    private var dialogShownAtRelaunch: [Bool] = []
    private var relaunchFails = false
    private var built: UpdateController?
    private var cliVersion = VersionBox("0.7.1")
    private var cliUpdater: FakeCLIUpdater!
    private var outdated: FakeOutdated!
    private var cliOutput: String? {
        get { cliVersion.value }
        set { cliVersion.value = newValue }
    }

    override func setUp() async throws {
        suite = "app.devmachine.mac.tests.\(UUID().uuidString)"
        preferences = UpdatePreferences(defaults: UserDefaults(suiteName: suite)!)
        http = ScriptedHTTP()
        installer = FakeInstaller()
        homebrew = FakeHomebrew()
        relaunched = []
        dialogShownAtRelaunch = []
        relaunchFails = false
        cliVersion = VersionBox("0.7.1")
        cliUpdater = FakeCLIUpdater(version: cliVersion)
        outdated = FakeOutdated()
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func controller(
        method: AppInstallMethod = .manual, runningTeam: String? = "TEAM123456", current: String? = "0.1.2",
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in throw CancellationError() }
    ) -> UpdateController {
        let cliVersion = cliVersion
        let outdated = outdated!
        let updates = UpdateController(dependencies: UpdateDependencies(
            currentVersion: current.flatMap { SemanticVersion($0) },
            appFeed: ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: http, userAgent: "Devmachine"),
            cliFeed: ReleaseFeed(url: ReleaseFeed.cliReleases, fetcher: http, userAgent: "Devmachine"),
            preferences: preferences,
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            sleep: sleep,
            detectInstallMethod: { method },
            runningTeamID: runningTeam,
            cliVersion: { cliVersion.value.map { CLIVersionReading(output: $0, method: .homebrew) } },
            installer: installer,
            homebrew: homebrew,
            cliUpdater: cliUpdater,
            packagesOutdated: { try outdated.read() },
            currentAppURL: URL(fileURLWithPath: "/Applications/Devmachine.app"),
            relaunch: { [weak self] url in
                guard let self else { return }
                relaunched.append(url)
                dialogShownAtRelaunch.append(built?.showsDialog ?? false)
                if relaunchFails { throw Boom() }
            }))
        built = updates
        return updates
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

    private func cliNoticeFor(installed: String, latest: String = "v0.8.0") async -> UpdateController {
        cliOutput = installed
        serve(app: "v0.1.2", cli: latest)
        let updates = controller()
        await updates.check(userInitiated: false)
        return updates
    }

    func testUpdatingTheCLIStreamsItsLogAndHidesTheNotice() async {
        let updates = await cliNoticeFor(installed: "0.7.23")
        XCTAssertTrue(updates.canUpdateCLIInApp)

        await updates.updateCLI()

        XCTAssertEqual(cliUpdater.runs, 1)
        XCTAssertEqual(updates.cliOutput, cliUpdater.lines)
        XCTAssertEqual(updates.cliPhase, .updated(SemanticVersion("0.8.0")!))
        XCTAssertNil(updates.cliNotice)
        XCTAssertTrue(relaunched.isEmpty)
        XCTAssertTrue(homebrew.runs.isEmpty)
    }

    func testAFailedCLIUpdateKeepsTheNoticeAndShowsTheExactError() async {
        cliUpdater.lines = ["==> CLI", "error: updating the CLI: checksum mismatch for devmachine_0.8.0.tar.gz"]
        cliUpdater.failure = CLIUpdateError.exited(1)
        let updates = await cliNoticeFor(installed: "0.7.23")

        await updates.updateCLI()

        guard case .failed(let state) = updates.cliPhase else { return XCTFail("\(updates.cliPhase)") }
        XCTAssertEqual(state.cause, "updating the CLI: checksum mismatch for devmachine_0.8.0.tar.gz")
        XCTAssertTrue(state.details.contains("==> CLI"))
        XCTAssertEqual(updates.cliNotice?.installed, SemanticVersion("0.7.23"))
    }

    func testRetryAfterAFailureRunsAgain() async {
        cliUpdater.failure = CLIUpdateError.exited(1)
        let updates = await cliNoticeFor(installed: "0.7.23")
        await updates.updateCLI()
        cliUpdater.failure = nil

        await updates.updateCLI()

        XCTAssertEqual(cliUpdater.runs, 2)
        XCTAssertEqual(updates.cliPhase, .updated(SemanticVersion("0.8.0")!))
    }

    func testAnOldCLIIsNeverRunAndAsksForOneManualUpdate() async {
        let updates = await cliNoticeFor(installed: "0.7.22")
        XCTAssertFalse(updates.canUpdateCLIInApp)

        await updates.updateCLI()

        XCTAssertEqual(cliUpdater.runs, 0)
        XCTAssertEqual(updates.cliPhase, .needsManualUpdate)
        XCTAssertNotNil(updates.cliNotice)
    }

    func testAnUnknownFlagMeansAManualUpdateNotAFallback() async {
        cliUpdater.lines = ["error: unknown flag: --cli-only"]
        cliUpdater.failure = CLIUpdateError.exited(1)
        let updates = await cliNoticeFor(installed: "0.7.23")

        await updates.updateCLI()

        XCTAssertEqual(cliUpdater.runs, 1)
        XCTAssertEqual(updates.cliPhase, .needsManualUpdate)
    }

    func testANewerCLIShowsItsOwnToastBesideTheApps() async {
        serve(app: "v0.1.3", cli: "v0.8.0")
        let updates = controller()
        await updates.check(userInitiated: false)
        XCTAssertTrue(updates.showsBanner)
        XCTAssertTrue(updates.showsCLIBanner)
    }

    func testNoNewerCLIShowsNoToast() async {
        let updates = await cliNoticeFor(installed: "0.8.0")
        XCTAssertFalse(updates.showsCLIBanner)
    }

    func testCLILaterIsSavedAndHidesTheToastUntilANewerCLI() async {
        let updates = await cliNoticeFor(installed: "0.7.23")
        updates.cliLater()

        XCTAssertFalse(updates.showsCLIBanner)
        XCTAssertEqual(preferences.cliLaterVersion, "0.8.0")
        XCTAssertNil(preferences.skippedVersion)
        XCTAssertNotNil(updates.cliNotice)

        let relaunched = await cliNoticeFor(installed: "0.7.23")
        XCTAssertFalse(relaunched.showsCLIBanner)

        let newer = await cliNoticeFor(installed: "0.7.23", latest: "v0.8.1")
        XCTAssertTrue(newer.showsCLIBanner)
    }

    func testCLILaterLeavesTheAppToastAlone() async {
        serve(app: "v0.1.3", cli: "v0.8.0")
        cliOutput = "0.7.23"
        let updates = controller()
        await updates.check(userInitiated: false)
        updates.cliLater()
        XCTAssertTrue(updates.showsBanner)
        XCTAssertFalse(updates.showsCLIBanner)
    }

    func testTheToastOnAnOldCLIShowsTheCommandAndRunsNothing() async {
        let updates = await cliNoticeFor(installed: "0.7.22")
        updates.showCLICommand()

        XCTAssertEqual(updates.cliPhase, .needsManualUpdate)
        XCTAssertTrue(updates.showsCLIBanner)
        XCTAssertEqual(cliUpdater.runs, 0)
        XCTAssertEqual(updates.cliNotice?.command, "brew upgrade devmachine")
    }

    func testTheToastStaysForAFailureAndAfterASuccessUntilClosed() async {
        cliUpdater.failure = CLIUpdateError.exited(1)
        let updates = await cliNoticeFor(installed: "0.7.23")
        await updates.updateCLI()
        XCTAssertTrue(updates.showsCLIBanner)

        cliUpdater.failure = nil
        await updates.updateCLI()
        XCTAssertEqual(updates.cliPhase, .updated(SemanticVersion("0.8.0")!))
        XCTAssertTrue(updates.showsCLIBanner)

        updates.closeCLIUpdated()
        XCTAssertFalse(updates.showsCLIBanner)
    }

    func testAVersionThatDidNotMoveIsAFailure() async {
        cliUpdater.installs = "0.7.23"
        let updates = await cliNoticeFor(installed: "0.7.23")

        await updates.updateCLI()

        guard case .failed(let state) = updates.cliPhase else { return XCTFail("\(updates.cliPhase)") }
        XCTAssertTrue(state.cause?.contains("0.7.23") ?? false, state.cause ?? "")
        XCTAssertNotNil(updates.cliNotice)
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

    func testTheDialogClosesBeforeQuittingBecauseASheetBlocksIt() async {
        serve(app: "v0.1.3")
        let updates = controller(method: .homebrew(brew: "/opt/homebrew/bin/brew"))
        await updates.check(userInitiated: false)
        updates.requestUpdate()
        XCTAssertTrue(updates.showsDialog)

        await updates.install()

        XCTAssertEqual(dialogShownAtRelaunch, [false])
        XCTAssertEqual(updates.phase, .relaunching)
    }

    func testStillRunningTenSecondsAfterTheUpdateAsksToQuitAndReopen() async {
        serve(app: "v0.1.3")
        let sleeps = SleepRecorder(allowed: 1)
        let updates = controller(method: .homebrew(brew: "/opt/homebrew/bin/brew"), sleep: { try await sleeps.sleep($0) })
        await updates.check(userInitiated: false)
        updates.requestUpdate()

        await updates.install()
        await updates.relaunchWatchdog?.value

        XCTAssertEqual(sleeps.delays, [10])
        XCTAssertEqual(updates.phase, .restartNeeded("0.1.3"))
        XCTAssertFalse(updates.phase.isBusy)
        XCTAssertTrue(updates.showsDialog)
        XCTAssertTrue(updates.showsBanner)
    }

    func testAHelperThatCannotStartAsksToQuitAndReopenAtOnce() async {
        relaunchFails = true
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)

        await updates.install()

        XCTAssertEqual(updates.phase, .restartNeeded("0.1.3"))
        XCTAssertNil(updates.relaunchWatchdog)
        XCTAssertTrue(updates.showsDialog)
    }

    func testQuitAndReopenTriesTheSameAppAgain() async {
        relaunchFails = true
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)
        await updates.install()
        relaunchFails = false

        updates.quitAndReopen()

        XCTAssertEqual(relaunched, Array(repeating: URL(fileURLWithPath: "/Applications/Devmachine.app"), count: 2))
        XCTAssertEqual(updates.phase, .relaunching)
        XCTAssertFalse(updates.showsDialog)
    }

    func testAnUpdateWaitingForARestartIsNotInstalledTwice() async {
        relaunchFails = true
        serve(app: "v0.1.3")
        let updates = controller()
        await updates.check(userInitiated: false)
        await updates.install()

        await updates.install()

        XCTAssertEqual(installer.installed, ["v0.1.3"])
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

    private static let newerPackages =
        #"{"pinned":"v32","latest":"v33","newer":true,"notes_url":"https://example.com/packages/v33"}"#
    private static let pinnedReport = Data(#"""
        {"cli":{"from":"0.7.31","to":"0.7.31","updated":false},
         "packages":{"from":"v32","to":"v33","pinned":true},"skills":{"updated":true}}
        """#.utf8)

    private func packagesNoticeFor(installed: String = "0.7.31", answer: String = newerPackages) async
        -> UpdateController {
        outdated.answer(answer)
        cliOutput = installed
        serve(app: "v0.1.2", cli: "v\(installed)")
        let updates = controller()
        await updates.check(userInitiated: false)
        return updates
    }

    func testACLIWithNoMachinesUpdatesThePinAndSkillsToo() async {
        cliUpdater.stdout = Data(#"""
            {"cli":{"from":"0.7.31","to":"0.8.0","updated":true},
             "packages":{"from":"v32","to":"v33","pinned":true},"skills":{"updated":true}}
            """#.utf8)
        let updates = await cliNoticeFor(installed: "0.7.31")

        await updates.updateCLI()

        XCTAssertEqual(cliUpdater.commands, [.noMachines])
        XCTAssertEqual(updates.cliPhase, .updated(SemanticVersion("0.8.0")!))
        XCTAssertEqual(updates.cliReport?.packagesTo, "v33")
        XCTAssertTrue(updates.cliReport?.skillsUpdated ?? false)
    }

    func testACLIBeforeNoMachinesStillRunsCLIOnly() async {
        let updates = await cliNoticeFor(installed: "0.7.30")

        await updates.updateCLI()

        XCTAssertEqual(cliUpdater.commands, [.cliOnly])
        XCTAssertNil(updates.cliReport)
        XCTAssertEqual(outdated.reads, 0)
    }

    func testANewerPackagesReleaseShowsTheCard() async {
        let updates = await packagesNoticeFor()

        XCTAssertEqual(updates.packagesNotice?.latest, "v33")
        XCTAssertEqual(updates.packagesNotice?.notesURL, URL(string: "https://example.com/packages/v33"))
        XCTAssertTrue(updates.showsPackagesBanner)
        XCTAssertEqual(outdated.reads, 1)
        XCTAssertEqual(cliUpdater.runs, 0)
    }

    func testAPinThatIsCurrentShowsNoCard() async {
        let updates = await packagesNoticeFor(answer: #"{"pinned":"v33","latest":"v33","newer":false}"#)
        XCTAssertNil(updates.packagesNotice)
        XCTAssertFalse(updates.showsPackagesBanner)
    }

    func testAnOlderCLIIsNeverAskedAboutPackages() async {
        let updates = await packagesNoticeFor(installed: "0.7.30")
        XCTAssertEqual(outdated.reads, 0)
        XCTAssertFalse(updates.showsPackagesBanner)
    }

    func testAFailedPackagesReadIsUnknownAndSilent() async {
        let updates = await packagesNoticeFor()
        outdated.fail()
        serve(app: "v0.1.2", cli: "v0.7.31")

        await updates.check(userInitiated: true)

        XCTAssertFalse(updates.showsPackagesBanner)
        XCTAssertNil(updates.checkError)

        let broken = await packagesNoticeFor(answer: "not json")
        XCTAssertFalse(broken.showsPackagesBanner)
        XCTAssertNil(broken.checkError)
    }

    func testNothingPinnedShowsNoCard() async {
        let updates = await packagesNoticeFor(answer: #"{"pinned":"","latest":"v32","newer":false}"#)
        XCTAssertFalse(updates.showsPackagesBanner)
    }

    func testUpdatingPackagesRunsOnlyThePinAndSkills() async {
        cliUpdater.lines = ["==> Packages", "  v32 → v33", "==> Skills", "  updated"]
        cliUpdater.stdout = Self.pinnedReport
        let updates = await packagesNoticeFor()

        await updates.updatePackages()

        XCTAssertEqual(cliUpdater.commands, [.packagesOnly])
        XCTAssertEqual(updates.packagesOutput, cliUpdater.lines)
        guard case .done(let report) = updates.packagesPhase else { return XCTFail("\(updates.packagesPhase)") }
        XCTAssertEqual(report?.packagesTo, "v33")
        XCTAssertNil(updates.packagesNotice)
        XCTAssertTrue(updates.showsPackagesBanner)
        XCTAssertEqual(cliVersion.value, "0.7.31")

        updates.closePackagesUpdated()
        XCTAssertFalse(updates.showsPackagesBanner)
    }

    func testAFailedPackagesUpdateShowsTheCauseAndRetries() async {
        cliUpdater.lines = ["==> Packages", "error: pinning the packages: no route to host"]
        cliUpdater.failure = CLIUpdateError.exited(1)
        let updates = await packagesNoticeFor()

        await updates.updatePackages()

        guard case .failed(let state) = updates.packagesPhase else { return XCTFail("\(updates.packagesPhase)") }
        XCTAssertEqual(state.cause, "pinning the packages: no route to host")
        XCTAssertTrue(state.details.contains("==> Packages"))
        XCTAssertTrue(updates.showsPackagesBanner)
        XCTAssertNotNil(updates.packagesNotice)

        cliUpdater.failure = nil
        cliUpdater.stdout = Self.pinnedReport
        await updates.updatePackages()
        XCTAssertEqual(cliUpdater.commands, [.packagesOnly, .packagesOnly])
        guard case .done = updates.packagesPhase else { return XCTFail("\(updates.packagesPhase)") }
    }

    func testAPinThatDidNotMoveIsAFailure() async {
        cliUpdater.stdout = Data(#"{"packages":{"from":"v32","to":"v32","pinned":false},"skills":{"updated":true}}"#.utf8)
        let updates = await packagesNoticeFor()

        await updates.updatePackages()

        guard case .failed(let state) = updates.packagesPhase else { return XCTFail("\(updates.packagesPhase)") }
        XCTAssertTrue(state.cause?.contains("v32") ?? false, state.cause ?? "")
    }

    func testAnUpdateThatReportsNothingIsAFailureNotADone() async {
        cliUpdater.stdout = Data()
        let updates = await packagesNoticeFor()

        await updates.updatePackages()

        guard case .failed(let state) = updates.packagesPhase else { return XCTFail("\(updates.packagesPhase)") }
        XCTAssertEqual(state.cause, "The CLI did not report what it pinned.")
        XCTAssertNotNil(updates.packagesNotice)
    }

    func testPackagesLaterIsSavedAndHidesTheCardUntilANewerRelease() async {
        let updates = await packagesNoticeFor()
        updates.packagesLater()

        XCTAssertFalse(updates.showsPackagesBanner)
        XCTAssertEqual(preferences.packagesLaterVersion, "v33")
        XCTAssertNil(preferences.cliLaterVersion)

        let relaunched = await packagesNoticeFor()
        XCTAssertFalse(relaunched.showsPackagesBanner)

        let newer = await packagesNoticeFor(
            answer: #"{"pinned":"v32","latest":"v34","newer":true,"notes_url":"https://example.com/packages/v34"}"#)
        XCTAssertTrue(newer.showsPackagesBanner)
    }

    func testTheCLICardsUpdateClearsThePackagesItPinned() async {
        outdated.answer(Self.newerPackages)
        cliUpdater.stdout = Data(#"""
            {"cli":{"from":"0.7.31","to":"0.8.0","updated":true},
             "packages":{"from":"v32","to":"v33","pinned":true},"skills":{"updated":true}}
            """#.utf8)
        let updates = await cliNoticeFor(installed: "0.7.31")
        XCTAssertTrue(updates.showsPackagesBanner)

        await updates.updateCLI()

        XCTAssertNil(updates.packagesNotice)
        XCTAssertFalse(updates.showsPackagesBanner)
    }

    func testAllThreeCardsStack() async {
        outdated.answer(Self.newerPackages)
        serve(app: "v0.1.3", cli: "v0.8.0")
        cliOutput = "0.7.31"
        let updates = controller()
        await updates.check(userInitiated: false)
        XCTAssertTrue(updates.showsBanner)
        XCTAssertTrue(updates.showsCLIBanner)
        XCTAssertTrue(updates.showsPackagesBanner)
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
