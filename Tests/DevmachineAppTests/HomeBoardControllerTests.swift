import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class HomeBoardControllerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeBoardControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeController(
        catalog: WidgetCatalog = DemoData.widgetCatalog, store: WidgetCatalogStore? = nil
    ) -> HomeBoardController {
        let catalogStore = store ?? WidgetCatalogStore(read: { catalog })
        catalogStore.seed(catalog)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: catalogStore, configPath: { nil })
        controller.defaultBoard = { DefaultBoard.make(usage: [UsageHarness(harness: "claude", package: "claude-code")]) }
        controller.open(configDirectory: root.appendingPathComponent("config").path)
        return controller
    }

    private var boardFile: URL { root.appendingPathComponent("config/boards/home.yml") }

    private let sourceBoard = """
        format: 1
        surface: home
        widgets:
          - id: disk
            title: Disk
            source: {kind: command, run: df, every: 60s}
            view: {kind: text}
            frame: {x: 24, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 1
          - id: tail
            title: Log
            source: {kind: command, run: tail, args: [-f, /var/log/system.log], mode: stream}
            view: {kind: text}
            frame: {x: 24, y: 200, w: 320, h: 320}
            size: large
            minimized: true
            z: 2
          - id: clock
            title: Clock
            source: {kind: provider, name: app/clock, every: 60s}
            view: {kind: app.clock}
            frame: {x: 400, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 3
        """

    func testSourceEntriesFollowMinimizeAndLeaveProvidersToTheRuntime() throws {
        let board = try BoardCodec.decode(sourceBoard)
        let entries = HomeBoardController.sourceEntries(
            board: board, resolve: { WidgetResolution.resolveInline($0) }, isOnScreen: { _ in true })
        XCTAssertEqual(entries.map(\.id), ["disk", "tail"])
        XCTAssertEqual(entries.map(\.isVisible), [true, false])
        XCTAssertEqual(entries.first?.source.needsApproval, true)
    }

    func testNothingIsVisibleWhenHomeIsNotOnScreen() throws {
        let board = try BoardCodec.decode(sourceBoard)
        let entries = HomeBoardController.sourceEntries(
            board: board, resolve: { WidgetResolution.resolveInline($0) }, isOnScreen: { _ in false })
        XCTAssertTrue(entries.allSatisfy { !$0.isVisible })
    }

    func testSourceWidgetsAreNotRuntimeJobs() throws {
        let controller = makeController()
        try sourceBoard.write(to: boardFile, atomically: true, encoding: .utf8)
        controller.start()
        controller.reload()
        XCTAssertEqual(controller.runtimeJobs().map(\.instanceID), ["clock"])
        XCTAssertEqual(controller.sourceEntries(isOnScreen: { _ in true }).map(\.id), ["disk", "tail"])
    }

    func testAWidgetChangedWithinOneReleaseRefreshesTheJobs() {
        let before = DemoData.widgetCatalog
        let edited = WidgetCatalog(
            engine: before.engine, packagesRelease: before.packagesRelease, widgets: Array(before.widgets.dropLast()))
        XCTAssertNotEqual(
            HomeJobsTrigger(board: nil, catalog: before, visible: .zero),
            HomeJobsTrigger(board: nil, catalog: edited, visible: .zero))
    }

    func testAnInjectedSourceControllerIsTheOneUsed() {
        let sources = WidgetSourceController(
            runners: WidgetSourceLive.runners(),
            approvalsFile: WidgetApprovalsFile(fileURL: root.appendingPathComponent("approvals.json")),
            historyStore: SparklineHistoryStore(directory: root.appendingPathComponent("history")), isDemo: false)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: WidgetCatalogStore(read: { DemoData.widgetCatalog }), sources: sources)
        XCTAssertTrue(controller.sources === sources)
    }

    func testOpeningWritesTheDefaultBoard() throws {
        let controller = makeController()
        XCTAssertEqual(controller.store?.board?.widgets.map(\.id), ["clock", "summary", "machines", "claude-usage"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: boardFile.path))
    }

    func testPlacesAddsOnlyEligibleWidgetsAndRemembersThem() throws {
        let controller = makeController()
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude"])
        let types = controller.store?.board?.widgets.map(\.type) ?? []
        XCTAssertFalse(types.contains("codex/usage"))
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertTrue(controller.store?.board?.widgets.map(\.type).contains("codex/usage") ?? false)
        let added = try XCTUnwrap(controller.store?.board?.widgets.first { $0.type == "codex/usage" })
        controller.remove(added.id)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertFalse(controller.store?.board?.widgets.map(\.type).contains("codex/usage") ?? true)
    }

    func testCanvasActionsChangeTheBoard() throws {
        let controller = makeController()
        controller.move("clock", to: BoardFrame(x: 400, y: 48, w: 320, h: 160))
        controller.setPreset("summary", preset: "medium")
        controller.setMinimized("machines", true)
        controller.bringToFront("clock")
        controller.resize("claude-usage", to: BoardFrame(x: 24, y: 360, w: 336, h: 160), sizes: ["small", "medium", "wide"])
        let board = try XCTUnwrap(controller.store?.board)
        let byID = Dictionary(uniqueKeysWithValues: board.widgets.map { ($0.id, $0) })
        XCTAssertEqual(byID["clock"]?.frame, BoardFrame(x: 400, y: 48, w: 320, h: 160))
        XCTAssertEqual(byID["clock"]?.z, 5)
        XCTAssertEqual(byID["summary"]?.size, "medium")
        XCTAssertEqual(byID["summary"]?.frame.w, 320)
        XCTAssertEqual(byID["machines"]?.minimized, true)
        XCTAssertEqual(byID["claude-usage"]?.size, "custom")
        controller.store?.flush()
        XCTAssertEqual(try BoardCodec.decode(String(contentsOf: boardFile, encoding: .utf8)), board)
    }

    func testBringingTheTopWidgetToFrontChangesNothing() throws {
        let controller = makeController()
        controller.bringToFront("claude-usage")
        XCTAssertEqual(controller.store?.board?.widgets.first { $0.id == "claude-usage" }?.z, 4)
    }

    func testAddingAWidgetPutsItOnAFreeSpotAndRemembersIt() throws {
        let controller = makeController()
        let codex = try XCTUnwrap(DemoData.widgetCatalog.widget(named: "codex/usage"))
        controller.add(codex, canvasWidth: 1280)
        let added = try XCTUnwrap(controller.store?.board?.widgets.first { $0.type == "codex/usage" })
        XCTAssertEqual(added.z, 5)
        controller.remove(added.id)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertFalse(controller.store?.board?.widgets.map(\.type).contains("codex/usage") ?? true)
    }

    func testResetBacksUpAndForgetsHomePlacements() throws {
        let controller = makeController()
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        controller.store?.flush()
        let before = try Data(contentsOf: boardFile)
        try controller.resetHome()
        XCTAssertEqual(try Data(contentsOf: boardFile.appendingPathExtension("bak")), before)
        XCTAssertEqual(controller.store?.board?.widgets.map(\.id), ["clock", "summary", "machines", "claude-usage"])
        let placements = WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")).load()
        XCTAssertFalse(placements.contains("codex/usage", on: "home"))
    }

    func testHomeSavesKeepTheStackPlacements() throws {
        let controller = makeController()
        let file = WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json"))
        var stack = WidgetPlacements()
        stack.insert("devmachine-app/links", on: "context-sidebar")
        try file.save(stack, surface: "context-sidebar")
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertTrue(file.load().contains("codex/usage", on: "home"))
        XCTAssertTrue(file.load().contains("devmachine-app/links", on: "context-sidebar"))
        try controller.resetHome()
        XCTAssertFalse(file.load().contains("codex/usage", on: "home"))
        XCTAssertTrue(file.load().contains("devmachine-app/links", on: "context-sidebar"))
    }

    func testResetWithoutAConfigurationFails() {
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: WidgetCatalogStore(read: { DemoData.widgetCatalog }))
        XCTAssertThrowsError(try controller.resetHome()) { error in
            XCTAssertEqual(error as? HomeBoardError, .noConfiguration)
        }
    }

    func testAMinimizedWidgetHasAnInactiveJob() throws {
        let controller = makeController()
        controller.setMinimized("claude-usage", true)
        let job = try XCTUnwrap(controller.runtimeJobs().first { $0.instanceID == "claude-usage" })
        XCTAssertFalse(job.isActive)
        XCTAssertEqual(job.key, WidgetRefreshKey(provider: "app/harness-usage", args: ["harness": "claude"]))
    }

    func testAWidgetOffScreenHasAnInactiveJob() throws {
        let controller = makeController()
        let jobs = controller.runtimeJobs(isOnScreen: { $0.id != "clock" })
        XCTAssertEqual(jobs.first { $0.instanceID == "clock" }?.isActive, false)
        XCTAssertEqual(jobs.first { $0.instanceID == "summary" }?.isActive, true)
    }

    func testDemoUsageWidgetsFixTheirHarness() throws {
        let codex = try XCTUnwrap(DemoData.widgetCatalog.widget(named: "codex/usage"))
        XCTAssertTrue(codex.inputs.isEmpty)
        XCTAssertEqual(codex.source.name, "app/harness-usage")
        XCTAssertEqual(WidgetPlacer.harness(of: codex), "codex")
    }

    func testReloadReadsTheCatalogAgain() async throws {
        let reads = ReadCounter()
        let catalog = DemoData.widgetCatalog
        let store = WidgetCatalogStore(read: {
            reads.increment()
            return catalog
        })
        let controller = makeController(store: store)
        controller.reload()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(reads.value, 0)
        controller.start()
        XCTAssertEqual(reads.value, 0)
        controller.reload()
        try await waitUntil { reads.value == 1 }
    }

    func testABoardsFolderDeletedAndRecreatedIsStillWatched() async throws {
        let controller = makeController()
        try FileManager.default.removeItem(at: boardFile.deletingLastPathComponent())
        try await waitUntil { FileManager.default.fileExists(atPath: self.boardFile.path) }
        let edited = Board(surface: "home", widgets: [
            BoardWidget(id: "clock", type: "devmachine-app/clock",
                        frame: BoardFrame(x: 24, y: 24, w: 320, h: 160), size: "medium", z: 1),
        ])
        try Data(BoardCodec.encode(edited).utf8).write(to: boardFile, options: .atomic)
        try await waitUntil { controller.store?.board == edited }
    }

    func testAFailedPlacementsSaveIsReportedAndKeptInMemory() throws {
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let catalogStore = WidgetCatalogStore(read: { DemoData.widgetCatalog })
        catalogStore.seed(DemoData.widgetCatalog)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: blocker.appendingPathComponent("widget-placements.json")),
            catalog: catalogStore)
        controller.defaultBoard = { DefaultBoard.make(usage: []) }
        controller.open(configDirectory: root.appendingPathComponent("config").path)
        XCTAssertNil(controller.placementsError)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertNotNil(controller.placementsError)
        let added = try XCTUnwrap(controller.store?.board?.widgets.first { $0.type == "codex/usage" })
        controller.remove(added.id)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertFalse(controller.store?.board?.widgets.map(\.type).contains("codex/usage") ?? true)
    }

    func testASuccessfulPlacementsSaveClearsTheError() throws {
        let folder = root.appendingPathComponent("support")
        try Data("x".utf8).write(to: folder)
        let catalogStore = WidgetCatalogStore(read: { DemoData.widgetCatalog })
        catalogStore.seed(DemoData.widgetCatalog)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: folder.appendingPathComponent("widget-placements.json")),
            catalog: catalogStore)
        controller.defaultBoard = { DefaultBoard.make(usage: []) }
        controller.open(configDirectory: root.appendingPathComponent("config").path)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude"])
        XCTAssertNotNil(controller.placementsError)
        try FileManager.default.removeItem(at: folder)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertNil(controller.placementsError)
    }

    func testDismissingThePlacementsErrorHidesIt() throws {
        let folder = root.appendingPathComponent("support")
        try Data("x".utf8).write(to: folder)
        let catalogStore = WidgetCatalogStore(read: { DemoData.widgetCatalog })
        catalogStore.seed(DemoData.widgetCatalog)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: folder.appendingPathComponent("widget-placements.json")),
            catalog: catalogStore)
        controller.defaultBoard = { DefaultBoard.make(usage: []) }
        controller.open(configDirectory: root.appendingPathComponent("config").path)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude"])
        XCTAssertNotNil(controller.placementsError)
        controller.dismissPlacementsError()
        XCTAssertNil(controller.placementsError)
    }

    func testAddingToABrokenBoardFailsAndChangesNothing() throws {
        try FileManager.default.createDirectory(at: boardFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("widgets: [unclosed\n".utf8).write(to: boardFile)
        let controller = makeController()
        let before = try String(contentsOf: boardFile, encoding: .utf8)
        let clock = try XCTUnwrap(DemoData.widgetCatalog.widgets.first { $0.name == "devmachine-app/clock" })
        XCTAssertFalse(controller.add(clock, canvasWidth: 1280))
        XCTAssertEqual(try String(contentsOf: boardFile, encoding: .utf8), before)
        XCTAssertEqual(controller.addBlockedReason, HomeBoardCopy.invalidNote)
    }

    func testAddingToAnOpenBoardSucceeds() throws {
        let controller = makeController()
        let clock = try XCTUnwrap(DemoData.widgetCatalog.widgets.first { $0.name == "devmachine-app/clock" })
        XCTAssertNil(controller.addBlockedReason)
        XCTAssertTrue(controller.add(clock, canvasWidth: 1280))
        XCTAssertEqual(controller.store?.board?.widgets.filter { $0.type == "devmachine-app/clock" }.count, 2)
    }

    func testAddingBeforeTheBoardIsOpenFails() throws {
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: WidgetCatalogStore(read: { DemoData.widgetCatalog }))
        let clock = try XCTUnwrap(DemoData.widgetCatalog.widgets.first { $0.name == "devmachine-app/clock" })
        XCTAssertFalse(controller.add(clock, canvasWidth: 1280))
        XCTAssertEqual(controller.addBlockedReason, "Home is not ready yet.")
    }

    func testReloadOpensTheBoardOnceTheConfigurationIsKnown() async throws {
        let configPath = root.appendingPathComponent("config").path
        let answers = ConfigAnswers([nil, configPath])
        let catalogStore = WidgetCatalogStore(read: { DemoData.widgetCatalog })
        catalogStore.seed(DemoData.widgetCatalog)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: catalogStore,
            configPath: { answers.next() })
        controller.defaultBoard = { DefaultBoard.make(usage: []) }
        controller.start()
        try await waitUntil { answers.calls == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(controller.store)
        controller.reload()
        try await waitUntil { controller.store != nil }
        XCTAssertEqual(controller.store?.fileURL, boardFile)
        controller.reload()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(answers.calls, 2)
    }

    func testResetWithoutAConfigurationFolderKeepsThePlacements() throws {
        let controller = makeController()
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        let placementsURL = root.appendingPathComponent("widget-placements.json")
        let before = try Data(contentsOf: placementsURL)
        try FileManager.default.removeItem(at: root.appendingPathComponent("config"))
        XCTAssertThrowsError(try controller.resetHome()) { error in
            XCTAssertEqual(error as? HomeBoardError, .noConfigurationFolder)
        }
        XCTAssertEqual(try Data(contentsOf: placementsURL), before)
        XCTAssertTrue(WidgetPlacementsFile(fileURL: placementsURL).load().contains("codex/usage", on: "home"))
        let codexCount = controller.store?.board?.widgets.filter { $0.type == "codex/usage" }.count
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertEqual(controller.store?.board?.widgets.filter { $0.type == "codex/usage" }.count, codexCount)
    }

    func testAResetClearsThePlacementsError() throws {
        let support = root.appendingPathComponent("support")
        try Data("x".utf8).write(to: support)
        let catalogStore = WidgetCatalogStore(read: { DemoData.widgetCatalog })
        catalogStore.seed(DemoData.widgetCatalog)
        let placementsURL = support.appendingPathComponent("widget-placements.json")
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: placementsURL), catalog: catalogStore)
        controller.defaultBoard = { DefaultBoard.make(usage: []) }
        controller.open(configDirectory: root.appendingPathComponent("config").path)
        controller.applyPlaces(canvasWidth: 1280, enabledHarnesses: ["claude", "codex"])
        XCTAssertNotNil(controller.placementsError)
        try FileManager.default.removeItem(at: support)
        try controller.resetHome()
        XCTAssertNil(controller.placementsError)
        XCTAssertFalse(WidgetPlacementsFile(fileURL: placementsURL).load().contains("codex/usage", on: "home"))
    }

    func testThePlacementsFileCanBeMoved() {
        XCTAssertEqual(
            HomeBoardController.placementsURL(environment: ["DEVMACHINE_WIDGET_PLACEMENTS": "/tmp/dm/p.json"]).path,
            "/tmp/dm/p.json")
        XCTAssertEqual(HomeBoardController.placementsURL(environment: [:]), WidgetPlacementsFile.defaultFileURL)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met within \(timeout)s") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class ConfigAnswers: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String?]
    private var count = 0

    init(_ answers: [String?]) { self.answers = answers }

    var calls: Int { lock.withLock { count } }

    func next() -> String? {
        lock.withLock {
            count += 1
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }
}
