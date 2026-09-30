import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DemoSnapshotsTests: XCTestCase {
    override func tearDown() async throws {
        unsetenv("DEVMACHINE_DEMO")
        unsetenv("DEVMACHINE_DEMO_SNAPSHOTS")
        unsetenv("DEVMACHINE_DEMO_LOADING")
        DemoSnapshots.subdomainsInitialTab = .sites
        DemoSnapshots.setupInitialSection = .connection
        try await super.tearDown()
    }

    func testTargetDirectoryIsNilWithNeitherVariableSet() {
        unsetenv("DEVMACHINE_DEMO")
        unsetenv("DEVMACHINE_DEMO_SNAPSHOTS")
        XCTAssertNil(DemoSnapshots.targetDirectory)
    }

    func testTargetDirectoryIsNilWithoutDemoMode() {
        unsetenv("DEVMACHINE_DEMO")
        setenv("DEVMACHINE_DEMO_SNAPSHOTS", "/tmp/devmachine-shots", 1)
        XCTAssertNil(DemoSnapshots.targetDirectory)
    }

    func testTargetDirectoryIsNilWithDemoModeButNoSnapshotDirectory() {
        setenv("DEVMACHINE_DEMO", "1", 1)
        unsetenv("DEVMACHINE_DEMO_SNAPSHOTS")
        XCTAssertNil(DemoSnapshots.targetDirectory)
    }

    func testTargetDirectoryIsNilForAnEmptyPath() {
        setenv("DEVMACHINE_DEMO", "1", 1)
        setenv("DEVMACHINE_DEMO_SNAPSHOTS", "", 1)
        XCTAssertNil(DemoSnapshots.targetDirectory)
    }

    func testTargetDirectoryReadsTheGivenPath() {
        setenv("DEVMACHINE_DEMO", "1", 1)
        setenv("DEVMACHINE_DEMO_SNAPSHOTS", "/tmp/devmachine-shots", 1)
        XCTAssertEqual(DemoSnapshots.targetDirectory?.path, "/tmp/devmachine-shots")
    }

    func testEveryScreenHasAUniqueNumberedFileName() {
        let names = DemoSnapshots.screens.map(\.fileName)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            XCTAssertTrue(name.hasSuffix(".png"))
        }
    }

    func testScreensAreNumberedInCaptureOrder() {
        let numbers = DemoSnapshots.screens.map { screen in
            String(screen.fileName.prefix(while: \.isNumber))
        }
        XCTAssertEqual(numbers, numbers.sorted())
        XCTAssertEqual(numbers.first, "00")
        XCTAssertEqual(numbers.last, "10")
    }

    func testEveryScreenHasAUniqueID() {
        let ids = DemoSnapshots.screens.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryScreenWaitsBeforeItIsCaptured() {
        for screen in DemoSnapshots.screens {
            XCTAssertGreaterThan(screen.settleNanoseconds, 0)
        }
    }

    func testThereAreExactlyElevenScreens() {
        XCTAssertEqual(DemoSnapshots.screens.count, 11)
    }

    func testTheFirstScreenIsHomeWithTheMachineCards() {
        XCTAssertEqual(DemoSnapshots.screens[0].id, "home")
        XCTAssertEqual(DemoSnapshots.screens[0].fileName, "00-home.png")
    }

    func testTheNinthScreenShowsTheSessionDefaults() {
        XCTAssertEqual(DemoSnapshots.screens[8].fileName, "08-session-defaults.png")
    }

    func testSubdomainsInitialTabDefaultsToSites() {
        XCTAssertEqual(DemoSnapshots.subdomainsInitialTab, .sites)
    }

    func testSetupInitialSectionDefaultsToConnection() {
        XCTAssertEqual(DemoSnapshots.setupInitialSection, .connection)
    }
    func testTheLoadingWalkFollowsTheMainWalksNumbering() {
        let names = DemoSnapshots.skeletonScreens.map(\.fileName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(Set(names).isDisjoint(with: DemoSnapshots.screens.map(\.fileName)))
        let numbers = names.map { String($0.prefix(while: \.isNumber)) }
        XCTAssertEqual(numbers, numbers.sorted())
        XCTAssertEqual(numbers.first, "11")
    }

    func testLoadingIsHeldOnlyInsideDemoMode() {
        setenv("DEVMACHINE_DEMO_LOADING", "1", 1)
        unsetenv("DEVMACHINE_DEMO")
        XCTAssertFalse(DemoMode.holdsLoading)
        setenv("DEVMACHINE_DEMO", "1", 1)
        XCTAssertTrue(DemoMode.holdsLoading)
    }

    func testAWindowSizeIsReadAsWidthByHeight() {
        XCTAssertEqual(DemoSnapshots.parseWindowSize("1100x700"), NSSize(width: 1100, height: 700))
        XCTAssertNil(DemoSnapshots.parseWindowSize("1100"))
        XCTAssertNil(DemoSnapshots.parseWindowSize("100x100"))
    }
}
