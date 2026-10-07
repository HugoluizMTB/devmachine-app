import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class BoardEditingControllerTests: XCTestCase {
    private var root: URL!
    private var command: ScriptedSourceRunner!
    private var launcher: AppFakeLauncher!
    private var stacks: [StackBoardController] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoardEditingControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config/boards"), withIntermediateDirectories: true)
        command = ScriptedSourceRunner()
        launcher = AppFakeLauncher()
    }

    override func tearDown() async throws {
        stacks.forEach { $0.sources.stop() }
        stacks.removeAll()
        command.release()
        launcher.releaseAll()
        try? FileManager.default.removeItem(at: root)
    }

    private var config: String { root.appendingPathComponent("config").path }

    private let machines = CatalogWidget(
        name: "devmachine-app/machines", fits: ["canvas", "stack"],
        inputs: ["machines": CatalogInput(type: "choice", defaultValue: nil, summary: "Machines to show.", from: "machines", many: true)],
        source: CatalogSource(name: "app/machines", with: ["machines": "{{inputs.machines}}"], every: "90s"),
        viewKind: "app.machines", sizes: ["medium", "large"], defaultSize: "large", surfaces: ["home", "sidebar"])

    private var catalog: WidgetCatalog { WidgetCatalog(engine: "1.5", packagesRelease: "2026.10.07", widgets: [machines]) }

    private func home(_ text: String) throws -> HomeBoardController {
        try Data(text.utf8).write(to: root.appendingPathComponent("config/boards/home.yml"))
        let store = WidgetCatalogStore(read: { [catalog] in catalog })
        store.seed(catalog)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: store, configPath: { nil })
        controller.open(configDirectory: config)
        return controller
    }

    private func stack(_ surface: String, _ text: String) throws -> StackBoardController {
        try Data(text.utf8).write(to: BoardFiles.url(configDirectory: config, surface: surface))
        let store = WidgetCatalogStore(read: { [catalog] in catalog })
        store.seed(catalog)
        let environment = SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: [:]) },
            localEnvironment: [:], home: "/Users/alice", isExecutable: { _ in true })
        let sources = WidgetSourceController(
            runners: SourceRunners(command: command, url: command, prompt: command, session: command, launcher: launcher, environment: environment),
            approvalsFile: WidgetApprovalsFile(fileURL: root.appendingPathComponent("approvals.json")),
            historyStore: SparklineHistoryStore(directory: root.appendingPathComponent("history")), surface: surface,
            isDemo: false, startsTimer: false)
        let controller = StackBoardController(
            surface: surface, placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: store, configPath: { nil }, sources: sources)
        controller.open(configDirectory: config)
        stacks.append(controller)
        return controller
    }

    private func homeText() throws -> String {
        try String(contentsOf: root.appendingPathComponent("config/boards/home.yml"), encoding: .utf8)
    }

    private let homeBoard = """
        format: 1
        surface: home
        widgets:
          - id: machines
            type: devmachine-app/machines
            frame: {x: 24, y: 24, w: 384, h: 320}
            size: custom
            minimized: false
            z: 1
          - id: disk
            title: Disk
            source: {kind: command, run: df, every: 60s}
            view: {kind: text}
            frame: {x: 424, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 2

        """

    func testChoosingMachinesWritesAListAndLeavesTheRestAsItWas() throws {
        let controller = try home(homeBoard)
        XCTAssertEqual(controller.choices(for: "machines").map(\.name), ["machines"])
        XCTAssertTrue(controller.apply(.input(name: "machines", value: .list(["main"])), to: "machines"))
        controller.store?.flush()
        let text = try homeText()
        XCTAssertTrue(text.contains("    type: devmachine-app/machines\n    with: {machines: [main]}\n"), text)
        XCTAssertTrue(text.contains("    source: {kind: command, run: df, every: 60s}\n"), text)
        XCTAssertEqual(controller.value(of: "machines", in: "machines"), .list(["main"]))
        XCTAssertTrue(controller.apply(.input(name: "machines", value: nil), to: "machines"))
        controller.store?.flush()
        XCTAssertFalse(try homeText().contains("with:"))
    }

    func testAChoiceIsOfferedForARefusedEntry() throws {
        let controller = try home(homeBoard.replacingOccurrences(
            of: "    type: devmachine-app/machines\n", with: "    type: devmachine-app/machines\n    with: {machines: main}\n"))
        guard case .refused? = controller.resolution(of: controller.store!.board!.widgets[0]) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(controller.choices(for: "machines").map(\.name), ["machines"])
    }

    func testAnInlineEntryOffersNoChoice() throws {
        XCTAssertEqual(try home(homeBoard).choices(for: "disk"), [])
    }

    func testATitleEditKeepsTheInlineTreesByteForByte() throws {
        let controller = try home(homeBoard)
        var inline = try XCTUnwrap(controller.editableEntry("disk")?.inline)
        inline.title = "Disk use"
        XCTAssertTrue(controller.apply(.inline(inline), to: "disk"))
        controller.store?.flush()
        let text = try homeText()
        XCTAssertTrue(text.contains("    title: Disk use\n    source: {kind: command, run: df, every: 60s}\n    view: {kind: text}\n"), text)
    }

    func testATypedEditWritesTheOverrides() throws {
        let controller = try home(homeBoard)
        XCTAssertTrue(controller.apply(.typed(title: "Servers", with: ["machines": .list(["main"])], every: "2m"), to: "machines"))
        controller.store?.flush()
        XCTAssertTrue(try homeText().contains(
            "    type: devmachine-app/machines\n    title: Servers\n    with: {machines: [main]}\n    every: 2m\n"))
        XCTAssertFalse(controller.apply(.typed(title: "x", with: [:], every: nil), to: "disk"))
    }

    func testAddingAnInlineWidgetOnHomeTakesAFreeSpotAndAnIDFromItsTitle() throws {
        let controller = try home(homeBoard)
        let inline = try XCTUnwrap(controller.editableEntry("disk")?.inline)
        let id = controller.addInline(inline, title: "Disk", preset: "medium")
        XCTAssertEqual(id, "disk-2")
        let added = try XCTUnwrap(controller.store?.board?.widgets.last)
        XCTAssertEqual(added.size, "medium")
        XCTAssertFalse(controller.store!.board!.widgets.dropLast().contains { $0.frame.rect.intersects(added.frame.rect) })
    }

    func testAStackEditAndAnInlineAddUseTheSameAPI() throws {
        let controller = try stack("sidebar", """
            format: 1
            surface: sidebar
            widgets:
              - id: machines
                type: devmachine-app/machines
                size: auto

            """)
        XCTAssertEqual(controller.choices(for: "machines").map(\.name), ["machines"])
        XCTAssertTrue(controller.apply(.input(name: "machines", value: .list(["here"])), to: "machines"))
        XCTAssertEqual(controller.board.entries[0].with["machines"], .list(["here"]))
        let inline = try BoardCodec.decodeStack("""
            format: 1
            surface: sidebar
            widgets:
              - id: x
                title: Uptime
                source: {kind: command, run: uptime, every: 60s}
                view: {kind: text}

            """).entries[0].inline!
        XCTAssertEqual(controller.addInline(inline, title: "Uptime", preset: "medium"), "uptime")
        XCTAssertNil(controller.board.entries.last?.size)
    }

    func testAFullMenuBarRefusesAnInlineAdd() throws {
        let controller = try stack("menubar", """
            format: 1
            surface: menubar
            widgets:
              - id: a
                type: devmachine-app/brand
              - id: b
                type: devmachine-app/open-pull-requests
              - id: c
                title: Up
                source: {kind: command, run: uptime, every: 60s}
                view: {kind: text}

            """)
        let inline = try XCTUnwrap(controller.board.entries[2].inline)
        XCTAssertNil(controller.addInline(inline, title: "Up", preset: "medium"))
    }

    func testNothingIsWrittenWhileTheFileIsInvalid() throws {
        let controller = try home("format: 1\nsurface: home\nwidgets: [\n")
        XCTAssertFalse(controller.apply(.input(name: "machines", value: .list(["main"])), to: "machines"))
        XCTAssertFalse(controller.canEdit)
    }
}
