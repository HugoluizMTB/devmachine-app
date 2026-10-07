import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class VersionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ value: String?) { self.value = value }
    func get() -> String? { lock.withLock { value } }
    func set(_ next: String?) { lock.withLock { value = next } }
}

private final class FakeUpdater: CLIUpdating, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [CLIUpdateCommand] = []
    let fails: Bool
    let onRun: @Sendable () -> Void

    init(fails: Bool = false, onRun: @escaping @Sendable () -> Void = {}) {
        self.fails = fails
        self.onRun = onRun
    }

    var commands: [CLIUpdateCommand] { lock.withLock { recorded } }

    func run(_ command: CLIUpdateCommand, output: @escaping @Sendable (String) -> Void) async throws -> Data {
        lock.withLock { recorded.append(command) }
        output("Updating devmachine")
        if fails {
            output("error: no network")
            throw CLIUpdateError.exited(1)
        }
        onRun()
        return Data()
    }
}

@MainActor
final class WidgetCompatibilityStoreTests: XCTestCase {
    private let manifest = WidgetAppManifest(
        engine: "1.0", requiresCLI: SemanticVersion(major: 0, minor: 9, patch: 0), requiresPackagesTag: "v39")
    private let pinned = PackagesOutdated(pinned: "v39", latest: "v39", newer: false, notesURL: nil)

    func testAnOldCLIShowsTheGapAndRunsTheCLIOnlyUpdate() async {
        let version = VersionBox("devmachine 0.8.1")
        let updater = FakeUpdater(onRun: { version.set("devmachine 0.9.0") })
        let pinned = self.pinned
        let store = WidgetCompatibilityStore(dependencies: WidgetCompatibilityDependencies(
            cliVersion: { version.get() }, packagesOutdated: { pinned }, updater: updater, manifest: manifest))
        var updated = false
        store.onUpdated = { updated = true }

        await store.check()
        XCTAssertEqual(store.gap?.command, .cliOnly)

        await store.runUpdate()
        XCTAssertEqual(updater.commands, [.cliOnly])
        XCTAssertNil(store.gap)
        XCTAssertEqual(store.status, .ok)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(updated)
    }

    func testACLIOnlyUpdateThatLeavesPackagesBehindKeepsTheBannerWithTheNextCommand() async {
        let version = VersionBox("devmachine 0.7.0")
        let updater = FakeUpdater(onRun: { version.set("devmachine 0.9.0") })
        let old = PackagesOutdated(pinned: "v38", latest: "v39", newer: true, notesURL: nil)
        let store = WidgetCompatibilityStore(dependencies: WidgetCompatibilityDependencies(
            cliVersion: { version.get() }, packagesOutdated: { old }, updater: updater, manifest: manifest))

        await store.check()
        XCTAssertEqual(store.gap?.command, .cliOnly)

        await store.runUpdate()
        XCTAssertEqual(updater.commands, [.cliOnly])
        XCTAssertEqual(store.gap?.command, .noMachines)
        XCTAssertEqual(store.gap?.cliBehind, false)
        XCTAssertEqual(store.gap?.packagesBehind, true)
        XCTAssertEqual(store.phase, .idle)
    }

    func testCheckNeverRunsTheUpdate() async {
        let updater = FakeUpdater()
        let pinned = self.pinned
        let store = WidgetCompatibilityStore(dependencies: WidgetCompatibilityDependencies(
            cliVersion: { "devmachine 0.8.1" }, packagesOutdated: { pinned }, updater: updater, manifest: manifest))
        await store.check()
        await store.check()
        XCTAssertNotNil(store.gap)
        XCTAssertEqual(updater.commands, [])
    }

    func testAFailedUpdateKeepsTheBannerWithTheOutput() async {
        let pinned = self.pinned
        let store = WidgetCompatibilityStore(dependencies: WidgetCompatibilityDependencies(
            cliVersion: { "devmachine 0.8.1" }, packagesOutdated: { pinned }, updater: FakeUpdater(fails: true),
            manifest: manifest))
        await store.check()
        await store.runUpdate()
        guard case let .failed(error) = store.phase else { return XCTFail("not failed") }
        XCTAssertTrue(error.details.contains("error: no network"))
        XCTAssertNotNil(store.gap)
    }

    func testAGapClosedOutsideTheAppClearsAnOldFailure() async {
        let version = VersionBox("devmachine 0.8.1")
        let pinned = self.pinned
        let store = WidgetCompatibilityStore(dependencies: WidgetCompatibilityDependencies(
            cliVersion: { version.get() }, packagesOutdated: { pinned }, updater: FakeUpdater(fails: true),
            manifest: manifest))
        await store.check()
        await store.runUpdate()
        version.set("devmachine 0.9.0")
        await store.check()
        XCTAssertNil(store.gap)
        XCTAssertEqual(store.phase, .idle)
    }

    func testNothingReadableShowsNothing() async {
        let store = WidgetCompatibilityStore(dependencies: .demo)
        await store.check()
        XCTAssertEqual(store.status, .unknown)
        XCTAssertNil(store.gap)
    }
}
