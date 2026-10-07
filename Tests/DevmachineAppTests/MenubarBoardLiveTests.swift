import XCTest
@testable import DevmachineCore

/// Runs the real CLI named by `DEVMACHINE_WIDGETS_E2E` against a temp
/// configuration it makes itself (only machine `here`, `self: true`), so the
/// real config folder is never read or written. Skipped otherwise.
@MainActor
final class MenubarBoardLiveTests: XCTestCase {
    private struct Run {
        let status: Int32
        let stdout: String
        let stderr: String
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
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenubarBoardLiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        try Data("machines:\n  - name: here\n    self: true\n".utf8)
            .write(to: folder.appendingPathComponent("config.yml"))
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
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(
            status: process.terminationStatus, stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self))
    }

    private func appWritten(_ surface: String, _ config: String) -> (StackBoardStore, URL) {
        let url = BoardFiles.url(configDirectory: config, surface: surface)
        let store = StackBoardStore(
            fileURL: url, surface: surface, makeDefault: { DefaultStackBoard.make(surface: surface) })
        store.load()
        return (store, url)
    }

    func testTheCLIReadsTheAppsDefaultMenubarBoards() throws {
        let (cli, config) = try setting()
        for surface in DefaultStackBoard.menubarSurfaces {
            let (_, url) = appWritten(surface, config)
            let validate = try run(cli, config, ["widgets", "validate", url.path])
            XCTAssertEqual(validate.status, 0, surface + validate.stdout + validate.stderr)
            let list = try run(cli, config, ["widgets", "list", "--board", surface])
            XCTAssertEqual(list.status, 0, list.stderr)
        }
    }

    func testTheCLIRefusesAFourthSlotAndASlotSize() throws {
        let (cli, config) = try setting()
        let (_, url) = appWritten(DefaultStackBoard.menubar, config)
        let original = try String(contentsOf: url, encoding: .utf8)
        let four = original + "  - id: a\n    type: acme/a\n  - id: b\n    type: acme/b\n"
        try Data(four.utf8).write(to: url, options: .atomic)
        let full = try run(cli, config, ["widgets", "validate", url.path])
        XCTAssertNotEqual(full.status, 0)
        XCTAssertTrue((full.stdout + full.stderr).contains("the menubar holds 3 widgets"), full.stdout + full.stderr)
        try Data((original + "    size: small\n").utf8).write(to: url, options: .atomic)
        let sized = try run(cli, config, ["widgets", "validate", url.path])
        XCTAssertNotEqual(sized.status, 0)
        XCTAssertTrue((sized.stdout + sized.stderr).contains("has no size"), sized.stdout + sized.stderr)
    }

    func testTheCLIMovesATabAndKeepsAnInlineEntry() throws {
        let (cli, config) = try setting()
        let (store, url) = appWritten(DefaultStackBoard.menubarPanel, config)
        let inline = """
              - id: log
                title: Deploy log
                source: {kind: command, run: tail, args: ["-n", "20", "deploy.log"], every: 60s}
                view: {kind: text}
                size: medium

            """
        try Data((String(contentsOf: url, encoding: .utf8) + inline).utf8).write(to: url, options: .atomic)
        let move = try run(
            cli, config, ["widgets", "move", "usage-panel", "--before", "pull-requests-panel", "--board", "menubar-panel"])
        XCTAssertEqual(move.status, 0, move.stderr)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains(inline.trimmingCharacters(in: .newlines)), text)
        store.load()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.board?.entries.map(\.id), ["usage-panel", "pull-requests-panel", "log"])
    }
}
