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
        DemoSnapshots.paletteInitialQuery = ""
        DemoData.typedAtPrompt = [:]
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
        XCTAssertEqual(numbers.first, "01")
        XCTAssertEqual(numbers.last, "23")
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

    func testTheWalkWritesEveryImageTheWebsiteShows() {
        XCTAssertEqual(DemoSnapshots.screens.map(\.fileName), [
            "01-sessions.png", "02-session-claude.png", "03-pull-requests.png",
            "04-subdomains-sites.png", "05-subdomains-dns-cloudflare.png", "06-stats.png",
            "07-settings-health.png", "08-session-defaults.png", "09-onboarding.png",
            "10-publish-port.png", "18-operator.png", "19-home.png",
            "20-menubar-usage.png", "21-command-palette.png", "22-drop-files.png",
            "23-preview.png",
        ])
    }

    func testTheLastScreenShowsAPreviewTab() {
        XCTAssertEqual(DemoSnapshots.screens.last?.id, "preview")
        XCTAssertEqual(DemoSnapshots.screens.last?.fileName, "23-preview.png")
    }

    func testThePreviewScreenOpensAnAcmeDevServerSession() {
        XCTAssertEqual(DemoSnapshots.previewSession.alias, "acme-devmachine")
        XCTAssertTrue(DemoData.sessionsByAlias["acme-devmachine"]?.contains {
            $0.name == DemoSnapshots.previewSession.name } ?? false)
    }

    func testTheDropScreenTargetsAcmesClaudeSession() {
        XCTAssertEqual(
            DemoSnapshots.dropKind,
            .remote(alias: "acme-devmachine", session: "claude \u{2014} payments refactor"))
        let sessions = DemoData.sessionsByAlias["acme-devmachine"]?.map(\.name) ?? []
        guard case let .remote(_, session) = DemoSnapshots.dropKind else {
            return XCTFail("the drop screen must show a remote session")
        }
        XCTAssertTrue(sessions.contains(session))
    }

    func testTheDroppedPathIsWhatAClaudeUploadTypes() {
        XCTAssertEqual(
            DemoSnapshots.droppedPath,
            "/home/acme/.claude/image-cache/devmachine-app/mockup-20260930-143012.png")
    }

    func testTheDropScreenTypesTheSentenceAroundThePath() {
        XCTAssertEqual(
            DemoSnapshots.dropPrompt,
            "look at /home/acme/.claude/image-cache/devmachine-app/mockup-20260930-143012.png"
            + " and match the header")
    }

    func testThePaletteOpensEmptyOutsideTheScreenshotWalk() {
        XCTAssertEqual(DemoSnapshots.paletteInitialQuery, "")
    }

    func testHomeIsCapturedAsNineteen() {
        XCTAssertEqual(DemoSnapshots.screens.first { $0.id == "home" }?.fileName, "19-home.png")
    }

    func testTheOperatorScreenSelectsTheOperatorSession() {
        XCTAssertEqual(
            DemoSnapshots.operatorSelection,
            .localSession(name: Workspace.operatorSession, path: DemoData.operatorPath))
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

    func testTheWalkIsCapturedAtABigScreenWindowSize() {
        unsetenv("DEVMACHINE_DEMO_WINDOW")
        XCTAssertEqual(DemoSnapshots.windowSize, NSSize(width: 2000, height: 1120))
    }

    func testMenubarPanesAndTheSheetAreFramedAsPanels() {
        let panels = DemoSnapshots.screens.filter { DemoSnapshots.chrome(for: $0.id) == .panel }.map(\.id)
        XCTAssertEqual(panels, ["pull-requests", "publish-port", "menubar-usage"])
    }

    func testEveryOtherScreenIsFramedAsAWindow() {
        XCTAssertEqual(DemoSnapshots.chrome(for: "home"), .window)
        XCTAssertEqual(DemoSnapshots.chrome(for: "onboarding"), .window)
    }

    func testTheWalkHidesScrollBarsThatAreNotInUse() {
        XCTAssertEqual(DemoSnapshots.scrollBarDefaults["AppleShowScrollBars"] as? String, "WhenScrolling")
    }

    func testTheUsagePaneIsTallEnoughForEveryModelRow() {
        XCTAssertEqual(DemoSnapshots.usagePaneHeight, 700)
    }

    func testTheWorktreeWalkIsItsOwnSetAndPickedByTheEnvironment() {
        let names = DemoSnapshots.worktreeScreens.map(\.fileName)
        XCTAssertEqual(names, [
            "31-git-worktrees.png", "32-worktree-remove.png", "33-worktrees-merged.png", "34-worktree-foreign.png",
        ])
        XCTAssertTrue(Set(names).isDisjoint(with: DemoSnapshots.screens.map(\.fileName)))
        XCTAssertEqual(DemoSnapshots.walk(environment: ["DEVMACHINE_DEMO_WALK": "worktrees"]).map(\.id),
                       DemoSnapshots.worktreeScreens.map(\.id))
        XCTAssertEqual(DemoSnapshots.walk(environment: [:]).map(\.id), DemoSnapshots.screens.map(\.id))
    }

    func testTheHarnessIconWalkCapturesTheSidebarOnItsOwn() {
        XCTAssertEqual(DemoSnapshots.harnessIconScreens.map(\.fileName), ["35-sidebar-harness-icons.png"])
        XCTAssertEqual(DemoSnapshots.walk(environment: ["DEVMACHINE_DEMO_WALK": "harness-icons"]).map(\.id),
                       DemoSnapshots.harnessIconScreens.map(\.id))
    }
}
