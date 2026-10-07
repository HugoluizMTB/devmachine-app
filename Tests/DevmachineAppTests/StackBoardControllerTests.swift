import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class StackBoardControllerTests: XCTestCase {
    private var root: URL!
    private var command: ScriptedSourceRunner!
    private var launcher: AppFakeLauncher!
    private var controllers: [StackBoardController] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StackBoardControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        command = ScriptedSourceRunner()
        launcher = AppFakeLauncher()
    }

    override func tearDown() async throws {
        controllers.forEach { $0.sources.stop() }
        controllers.removeAll()
        command.release()
        launcher.releaseAll()
        try? FileManager.default.removeItem(at: root)
    }

    private var config: String { root.appendingPathComponent("config").path }
    private func catalog(_ widgets: [CatalogWidget]) -> WidgetCatalog {
        WidgetCatalog(engine: "1.2", packagesRelease: "2026.10.07", widgets: widgets)
    }
    private var disk: CatalogWidget {
        CatalogWidget(
            name: "acme/disk", fits: ["stack"], source: CatalogSource(name: "app/machines", every: "60s"),
            viewKind: "app.machines", sizes: ["medium", "large"], defaultSize: "medium", places: ["context-sidebar"],
            surfaces: ["context-sidebar"])
    }
    private func file(_ surface: String) -> URL { BoardFiles.url(configDirectory: config, surface: surface) }
    private var placementsURL: URL { root.appendingPathComponent("widget-placements.json") }

    private func makeController(_ surface: String, catalog: WidgetCatalog? = nil, open: Bool = true) -> StackBoardController {
        let empty = WidgetCatalog(engine: "1.2", packagesRelease: "2026.10.07", widgets: [])
        let store = WidgetCatalogStore(read: { catalog ?? empty })
        if let catalog { store.seed(catalog) }
        let environment = SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: [:]) },
            localEnvironment: [:], home: "/Users/alice", isExecutable: { _ in true })
        let sources = WidgetSourceController(
            runners: SourceRunners(command: command, url: command, prompt: command, session: command, launcher: launcher, environment: environment),
            approvalsFile: WidgetApprovalsFile(fileURL: root.appendingPathComponent("approvals.json")),
            historyStore: SparklineHistoryStore(directory: root.appendingPathComponent("history")), surface: surface,
            isDemo: false, startsTimer: false)
        let controller = StackBoardController(
            surface: surface, placementsFile: WidgetPlacementsFile(fileURL: placementsURL), catalog: store,
            configPath: { nil }, sources: sources)
        if open { controller.open(configDirectory: config) }
        controllers.append(controller)
        return controller
    }

    private func write(_ text: String, _ surface: String) throws {
        try FileManager.default.createDirectory(at: file(surface).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file(surface), options: .atomic)
    }

    private func read(_ surface: String) throws -> StackBoard {
        try BoardCodec.decodeStack(String(contentsOf: file(surface), encoding: .utf8))
    }

    func testWithNoFileTheDefaultBoardsAreWrittenInTodaysOrder() throws {
        _ = makeController("sidebar")
        _ = makeController("context-sidebar")
        XCTAssertEqual(try read("sidebar"), DefaultStackBoard.make(surface: "sidebar"))
        XCTAssertEqual(try read("context-sidebar"), DefaultStackBoard.make(surface: "context-sidebar"))
    }

    func testEachSurfaceKeepsItsOwnStore() {
        let sidebar = makeController("sidebar")
        let context = makeController("context-sidebar")
        XCTAssertEqual(sidebar.store?.surface, "sidebar")
        XCTAssertEqual(context.store?.surface, "context-sidebar")
        XCTAssertEqual(sidebar.store?.fileURL, file("sidebar"))
        XCTAssertEqual(context.store?.fileURL, file("context-sidebar"))
    }

    func testWithNoConfigurationTheDefaultBoardDrawsReadOnly() {
        let controller = makeController("sidebar", open: false)
        XCTAssertNil(controller.store)
        XCTAssertEqual(controller.board, DefaultStackBoard.make(surface: "sidebar"))
        XCTAssertFalse(controller.canEdit)
        controller.remove("workspaces")
        XCTAssertEqual(controller.board.entries.map(\.id), ["workspaces"])
        if case .ready = controller.resolution(of: controller.board.entries[0]) {} else { XCTFail("workspaces must draw") }
    }

    func testAnInvalidFileOnFirstReadDrawsTheDefaultAndWritesNothing() throws {
        let broken = "format: 1\nsurface: sidebar\nwidgets:\n  - id: workspaces\n    type: devmachine-app/workspaces\n    frame: {x: 0, y: 0, w: 1, h: 1}\n"
        try write(broken, "sidebar")
        let controller = makeController("sidebar")
        XCTAssertNil(controller.store?.board)
        XCTAssertEqual(controller.board, DefaultStackBoard.make(surface: "sidebar"))
        XCTAssertFalse(controller.canEdit)
        XCTAssertEqual(controller.problem?.line, 6)
        controller.remove("workspaces")
        controller.store?.flush()
        XCTAssertEqual(try String(contentsOf: file("sidebar"), encoding: .utf8), broken)
        XCTAssertEqual(
            controller.addBlockedReason(for: try XCTUnwrap(controller.galleryEntries().first)),
            "The sidebar area cannot change until sidebar.yml can be read and written.")
    }

    func testEditsReachTheFile() throws {
        let controller = makeController("context-sidebar")
        controller.moveUp("links")
        controller.moveDown("shortcuts")
        controller.move("todo", toIndex: 0)
        controller.setCollapsed("shells", true)
        controller.setSize("monitors", .preset("large"))
        controller.remove("publish-port")
        controller.store?.flush()
        let board = try read("context-sidebar")
        XCTAssertEqual(board.entries.map(\.id), ["todo", "shortcuts", "monitors", "shells", "sub-agents", "links", "pull-requests"])
        XCTAssertEqual(board.entries.first { $0.id == "shells" }?.collapsed, true)
        XCTAssertEqual(board.entries.first { $0.id == "monitors" }?.size, .preset("large"))
    }

    func testPickingASizeOtherThanTheDefaultWritesIt() throws {
        try write("format: 1\nsurface: context-sidebar\nwidgets:\n  - id: disk\n    type: acme/disk\n", "context-sidebar")
        let controller = makeController("context-sidebar", catalog: catalog([disk]))
        controller.setSize("disk", .preset("large"))
        controller.store?.flush()
        XCTAssertEqual(try read("context-sidebar").entries.first?.size, .preset("large"))
    }

    func testADropNextToANeighbourReachesTheFile() throws {
        let controller = makeController("context-sidebar")
        controller.move("links", to: .before("shortcuts"))
        controller.store?.flush()
        XCTAssertEqual(try read("context-sidebar").entries.first?.id, "links")
    }

    func testRemovingWorkspacesLeavesAnEmptyStackAndTheGalleryOffersItOnce() throws {
        let controller = makeController("sidebar")
        let workspaces = try XCTUnwrap(controller.galleryEntries().first { $0.name == "devmachine-app/workspaces" })
        XCTAssertEqual(controller.addBlockedReason(for: workspaces), "Already in the sidebar area")
        XCTAssertFalse(controller.add(workspaces))
        controller.remove("workspaces")
        XCTAssertEqual(controller.board.entries, [])
        XCTAssertNil(controller.addBlockedReason(for: workspaces))
        XCTAssertTrue(controller.add(workspaces))
        XCTAssertFalse(controller.add(workspaces))
        controller.store?.flush()
        XCTAssertEqual(try read("sidebar").entries.map(\.id), ["workspaces"])
        XCTAssertTrue(WidgetPlacementsFile(fileURL: placementsURL).load().contains("devmachine-app/workspaces", on: "sidebar"))
    }

    func testAnUndecodablePlacementsFileMovesAsideAndTheAddGoesOn() throws {
        try Data("not json".utf8).write(to: placementsURL)
        let controller = makeController("sidebar")
        controller.remove("workspaces")
        let workspaces = try XCTUnwrap(controller.galleryEntries().first { $0.name == "devmachine-app/workspaces" })
        XCTAssertTrue(controller.add(workspaces))
        XCTAssertNil(controller.placementsError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: placementsURL.appendingPathExtension("broken").path))
        XCTAssertTrue(WidgetPlacementsFile(fileURL: placementsURL).load().contains("devmachine-app/workspaces", on: "sidebar"))
    }

    private var here: CatalogWidget {
        var widget = CatalogWidget(
            name: "acme/here", fits: ["stack"], context: ["path": "required"],
            source: CatalogSource(raw: .object([
                "kind": .string("command"), "run": .string("ls"), "args": .list([.string("{{context.path}}")]),
                "every": .string("60s"),
            ])),
            viewKind: "text", sizes: ["medium"], defaultSize: "medium", surfaces: ["context-sidebar"])
        widget.view = .object(["kind": .string("text")])
        return widget
    }

    func testSourcesRunWithTheAreaContextOnlyWhileShownAndExpanded() async throws {
        try write("""
            format: 1
            surface: context-sidebar
            widgets:
              - id: here
                type: acme/here

            """, "context-sidebar")
        let controller = makeController("context-sidebar", catalog: catalog([here]))
        controller.setContext(["path": "/home/alice/api"])
        controller.syncSources()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        controller.setVisible(true)
        await waitUntil { self.command.calls == 1 }
        XCTAssertEqual(command.requests[0].context["path"], "/home/alice/api")
        controller.setCollapsed("here", true)
        controller.syncSources()
        controller.setContext(["path": "/home/alice/web"])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
    }

    func testHidingTheAreaStopsItsSources() async throws {
        try write("""
            format: 1
            surface: context-sidebar
            widgets:
              - id: here
                type: acme/here

            """, "context-sidebar")
        command = ScriptedSourceRunner([.success(.output(.text("files")))], gated: true)
        let controller = makeController("context-sidebar", catalog: catalog([here]))
        controller.setContext(["path": "/home/alice/api"])
        controller.setVisible(true)
        await waitUntil { self.command.calls == 1 }
        XCTAssertTrue(controller.sources.state("here").isRunning)
        controller.setVisible(false)
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.sources.state("here").isRunning)
        command.release()
        await waitUntil { self.command.cancelled == 1 }
        XCTAssertNil(controller.sources.state("here").output)
        controller.setVisible(true)
        await waitUntil { self.command.calls == 2 }
        await waitUntil { controller.sources.state("here").output == .text("files") }
    }

    func testAReloadBeforeStartNeverAsksForTheConfiguration() async {
        let folder = config
        let asks = ReadCounter()
        let controller = StackBoardController(
            surface: "sidebar", placementsFile: WidgetPlacementsFile(fileURL: placementsURL),
            catalog: WidgetCatalogStore(read: { WidgetCatalog(engine: "1.2", packagesRelease: "", widgets: []) }),
            configPath: {
                asks.increment()
                return folder
            })
        controller.reload()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(asks.value, 0)
        XCTAssertNil(controller.store)
    }

    func testTheBoardSaysWhichCostlyContextItNeeds() throws {
        let controller = makeController("context-sidebar")
        XCTAssertTrue(controller.needsSessionContext)
        XCTAssertFalse(controller.needsGitContext)
        XCTAssertEqual(controller.leadEntryID(provider: "app/session-context"), "monitors")
        controller.setCollapsed("monitors", true)
        XCTAssertEqual(controller.leadEntryID(provider: "app/session-context"), "shells")
        for id in ["shells", "sub-agents", "todo", "pull-requests", "links"] { controller.remove(id) }
        XCTAssertFalse(controller.needsSessionContext)
        try write("""
            format: 1
            surface: context-sidebar
            widgets:
              - id: branch
                title: Branch
                source: {kind: command, run: echo, args: ["{{context.branch}}"], every: 30s}
                view: {kind: text}

            """, "context-sidebar")
        controller.start()
        controller.reload()
        XCTAssertEqual(controller.board.entries.map(\.id), ["branch"])
        XCTAssertTrue(controller.needsGitContext)
        controller.setCollapsed("branch", true)
        XCTAssertFalse(controller.needsGitContext)
    }

    func testAnInlineWidgetThatReadsPathOrHarnessNeedsSessionContext() throws {
        for reference in ["{{context.path}}", "{{context.harness}}"] {
            try write("""
                format: 1
                surface: context-sidebar
                widgets:
                  - id: here
                    title: Here
                    source: {kind: command, run: echo, args: ["\(reference)"], every: 30s}
                    view: {kind: text}

                """, "context-sidebar")
            let controller = makeController("context-sidebar")
            XCTAssertEqual(controller.board.entries.map(\.id), ["here"])
            XCTAssertNil(controller.leadEntryID(provider: "app/session-context"))
            XCTAssertTrue(controller.needsSessionContext, reference)
            controller.setCollapsed("here", true)
            XCTAssertFalse(controller.needsSessionContext, reference)
        }
    }

    func testAnInlineWidgetThatReadsOnlyTheSessionNeedsNoSessionContext() throws {
        try write("""
            format: 1
            surface: context-sidebar
            widgets:
              - id: here
                title: Here
                source: {kind: command, run: echo, args: ["{{context.session}}"], every: 30s}
                view: {kind: text}

            """, "context-sidebar")
        XCTAssertFalse(makeController("context-sidebar").needsSessionContext)
    }

    func testAPackageWidgetNeedsGitOnlyWhenItDeclaresRepoOrBranch() throws {
        try write("""
            format: 1
            surface: context-sidebar
            widgets:
              - id: here
                type: acme/here

            """, "context-sidebar")
        var reader = here
        let controller = makeController("context-sidebar", catalog: catalog([reader]))
        XCTAssertFalse(controller.needsGitContext)
        reader = CatalogWidget(
            name: "acme/here", fits: ["stack"], context: ["path": "required", "repo": "optional"],
            source: here.source, viewKind: "text", sizes: ["medium"], defaultSize: "medium", surfaces: ["context-sidebar"])
        reader.view = here.view
        controller.catalog.seed(catalog([reader]))
        XCTAssertTrue(controller.needsGitContext)
    }

    func testResetWritesTheDefaultKeepsABackupAndForgetsOnlyThisAreasPlacements() throws {
        var home = WidgetPlacements()
        home.insert("devmachine-app/clock", on: "home")
        try WidgetPlacementsFile(fileURL: placementsURL).save(home, surface: "home")
        let controller = makeController("sidebar")
        controller.applyPlaces()
        XCTAssertTrue(WidgetPlacementsFile(fileURL: placementsURL).load().contains("devmachine-app/workspaces", on: "sidebar"))
        controller.remove("workspaces")
        controller.store?.flush()
        try controller.reset()
        XCTAssertEqual(try read("sidebar"), DefaultStackBoard.make(surface: "sidebar"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("sidebar").appendingPathExtension("bak").path))
        let placements = WidgetPlacementsFile(fileURL: placementsURL).load()
        XCTAssertTrue(placements.contains("devmachine-app/clock", on: "home"))
        XCTAssertFalse(placements.contains("devmachine-app/workspaces", on: "sidebar"))
    }

    func testResetWithoutAConfigurationSaysWhy() {
        let controller = makeController("context-sidebar", open: false)
        XCTAssertThrowsError(try controller.reset()) { error in
            XCTAssertEqual(error as? StackBoardError, .noConfiguration(surface: "context-sidebar"))
            XCTAssertEqual(
                error.localizedDescription,
                "The context-sidebar area has no layout file yet: the devmachine CLI has not said where its configuration lives.")
        }
    }

    func testResetWithoutAConfigurationFolderSaysWhy() throws {
        let controller = makeController("sidebar", open: false)
        controller.open(configDirectory: root.appendingPathComponent("missing").path)
        XCTAssertThrowsError(try controller.reset()) { error in
            XCTAssertEqual(error as? StackBoardError, .noConfigurationFolder(surface: "sidebar"))
        }
    }

    func testPlacementsAddACatalogWidgetOnceAtTheEnd() throws {
        let controller = makeController("context-sidebar", catalog: catalog([disk]))
        controller.applyPlaces()
        controller.store?.flush()
        XCTAssertEqual(try read("context-sidebar").entries.last?.id, "disk")
        controller.remove("disk")
        controller.applyPlaces()
        XCTAssertFalse(controller.board.entries.contains { $0.type == "acme/disk" })
    }

    func testRuntimeJobsLeaveOutTheBuiltInSidebarWidgets() throws {
        let controller = makeController("context-sidebar", catalog: catalog([disk]))
        controller.applyPlaces()
        controller.setVisible(true)
        XCTAssertEqual(controller.runtimeJobs().count, 1)
    }
}
