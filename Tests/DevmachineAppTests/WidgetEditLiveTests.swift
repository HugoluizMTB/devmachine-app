import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

/// Runs the real CLI named by `DEVMACHINE_WIDGETS_E2E` against a temp
/// configuration it makes itself (only machine `here`, `self: true`), so the
/// real config folder is never read or written. Skipped otherwise.
/// `DEVMACHINE_WIDGETS_PACKAGES` names a packages checkout whose
/// `packages/devmachine-app` is copied into that configuration as a local package.
@MainActor
final class WidgetEditLiveTests: XCTestCase {
    private struct Run {
        let status: Int32
        let output: String
    }

    private var folder: URL?

    override func tearDown() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        super.tearDown()
    }

    private func setting() throws -> (cli: String, config: String) {
        guard let cli = ProcessInfo.processInfo.environment["DEVMACHINE_WIDGETS_E2E"], !cli.isEmpty else {
            throw XCTSkip("set DEVMACHINE_WIDGETS_E2E to a devmachine binary")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetEditLiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("boards"), withIntermediateDirectories: true)
        self.folder = folder
        try Data("machines:\n  - name: here\n    self: true\n".utf8).write(to: folder.appendingPathComponent("config.yml"))
        if let packages = ProcessInfo.processInfo.environment["DEVMACHINE_WIDGETS_PACKAGES"], !packages.isEmpty {
            let target = folder.appendingPathComponent("packages")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: packages).appendingPathComponent("packages/devmachine-app"),
                to: target.appendingPathComponent("devmachine-app"))
        }
        return (cli, folder.path)
    }

    private func requirePackages() throws {
        guard let packages = ProcessInfo.processInfo.environment["DEVMACHINE_WIDGETS_PACKAGES"], !packages.isEmpty else {
            throw XCTSkip("set DEVMACHINE_WIDGETS_PACKAGES to a packages checkout")
        }
    }

    private func run(_ cli: String, _ config: String, _ args: [String]) throws -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["DEVMACHINE_CONFIG"] = config
        environment["DEVMACHINE_KEYCHAIN"] = "off"
        environment["DEVMACHINE_NO_UPDATE_HINT"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    func testTheCLIValidatesWhatTheAppWrites() throws {
        let (cli, config) = try setting()
        var board = DefaultBoard.make(harnesses: ["claude", "codex"])
        board.widgets[0].with["machines"] = .list(["here"])
        board.widgets[0].titleOverride = "Servers"
        board.widgets[0].everyOverride = "2m"
        let home = BoardFiles.url(configDirectory: config, surface: "home")
        try Data(BoardCodec.encode(board).utf8).write(to: home)
        let validate = try run(cli, config, ["widgets", "validate", home.path])
        XCTAssertEqual(validate.status, 0, validate.output)
    }

    func testEveryTemplateTheAppMakesPassesTheCLI() throws {
        let (cli, config) = try setting()
        for template in InlineWidgetTemplate.allCases {
            var form = InlineWidgetForm(template: template)
            form.title = "Check"
            form.run = "uptime"
            form.url = "https://example.com"
            form.prompt = "Say hello"
            form.session = "main"
            let inline = try form.read(surface: "sidebar", id: "check").get()
            let text = BoardCodec.encodeStack(StackBoard(surface: "sidebar", entries: [StackEntry(id: "check", type: "", inline: inline)]))
            let file = BoardFiles.url(configDirectory: config, surface: "sidebar")
            try Data(text.utf8).write(to: file)
            let validate = try run(cli, config, ["widgets", "validate", file.path])
            XCTAssertEqual(validate.status, 0, "\(template): " + validate.output)
        }
    }

    func testTheAppReadsWhatWidgetsSetWrites() throws {
        try requirePackages()
        let (cli, config) = try setting()
        let home = BoardFiles.url(configDirectory: config, surface: "home")
        let store = BoardStore(fileURL: home, makeDefault: { DefaultBoard.make(harnesses: ["claude"]) })
        store.load()
        let before = try String(contentsOf: home, encoding: .utf8)
        let set = try run(cli, config, [
            "widgets", "set", "machines", "--board", "home", "--title", "Servers", "--every", "2m", "--set", "machines=here,main",
        ])
        XCTAssertEqual(set.status, 0, set.output)
        store.load()
        let machines = try XCTUnwrap(store.board?.widgets.first { $0.id == "machines" })
        XCTAssertEqual(machines.titleOverride, "Servers")
        XCTAssertEqual(machines.everyOverride, "2m")
        XCTAssertEqual(machines.with["machines"], .list(["here", "main"]))
        let after = try String(contentsOf: home, encoding: .utf8)
        let untouched = { (text: String) in text.components(separatedBy: "  - id: clock").last ?? "" }
        XCTAssertEqual(untouched(after), untouched(before))
    }

    func testBothRefuseAnEveryBelowTheFloorOnATypedEntry() throws {
        try requirePackages()
        let (cli, config) = try setting()
        let home = BoardFiles.url(configDirectory: config, surface: "home")
        let store = BoardStore(fileURL: home, makeDefault: { DefaultBoard.make(harnesses: ["claude"]) })
        store.load()
        let before = try String(contentsOf: home, encoding: .utf8)
        let set = try run(cli, config, ["widgets", "set", "machines", "--board", "home", "--every", "1s"])
        XCTAssertNotEqual(set.status, 0, set.output)
        XCTAssertTrue(set.output.contains("minimum") || set.output.contains("below"), set.output)
        XCTAssertEqual(try String(contentsOf: home, encoding: .utf8), before)

        let catalog = try WidgetCatalog.decode(Data(try run(cli, config, ["widgets", "list", "--format", "json"]).output.utf8))
        let catalogStore = WidgetCatalogStore(read: { catalog })
        catalogStore.seed(catalog)
        let controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: URL(fileURLWithPath: config).appendingPathComponent("widget-placements.json")),
            catalog: catalogStore, configPath: { nil })
        controller.open(configDirectory: config)
        let problem = try XCTUnwrap(controller.problem(with: .typed(title: nil, with: [:], every: "1s"), for: "machines"))
        XCTAssertTrue(problem.contains("minimum"), problem)
    }

    func testBothRefuseAnEveryBelowTheFloorAndAnInlineSourceEdit() throws {
        let (cli, config) = try setting()
        let home = BoardFiles.url(configDirectory: config, surface: "home")
        try Data(BoardCodec.encode(Board(surface: "home", widgets: [])).utf8).write(to: home)
        let inline = """
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

            """
        try Data(inline.utf8).write(to: home)
        let source = try run(cli, config, ["widgets", "set", "disk", "--board", "home", "--set", "run=du"])
        XCTAssertNotEqual(source.status, 0, source.output)
        let every = try run(cli, config, ["widgets", "set", "disk", "--board", "home", "--every", "1s"])
        XCTAssertNotEqual(every.status, 0, every.output)
        XCTAssertEqual(try String(contentsOf: home, encoding: .utf8), inline)
    }
}
