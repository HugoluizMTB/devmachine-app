import XCTest
@testable import DevmachineCore

/// Runs the real CLI named by `DEVMACHINE_WIDGETS_E2E` against a temp
/// configuration it makes itself (only machine `here`, `self: true`), so the
/// real config folder is never read or written. Skipped otherwise.
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
        return (cli, folder.path)
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
        let (cli, config) = try setting()
        let home = BoardFiles.url(configDirectory: config, surface: "home")
        let store = BoardStore(fileURL: home, makeDefault: { DefaultBoard.make(harnesses: ["claude"]) })
        store.load()
        let before = try String(contentsOf: home, encoding: .utf8)
        let set = try run(cli, config, [
            "widgets", "set", "machines", "--board", "home", "--title", "Servers", "--every", "2m", "--set", "machines=here,main",
        ])
        if set.status != 0, set.output.contains("release") || set.output.contains("not in the catalog") {
            throw XCTSkip("the CLI catalog lacks devmachine-app/machines (needs a packages release): \(set.output)")
        }
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
