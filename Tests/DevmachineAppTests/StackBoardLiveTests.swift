import XCTest
@testable import DevmachineCore

/// Runs the real CLI named by `DEVMACHINE_WIDGETS_E2E` against a temp
/// configuration it makes itself (only machine `here`, `self: true`), so the
/// real config folder is never read or written. Skipped otherwise.
@MainActor
final class StackBoardLiveTests: XCTestCase {
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
            .appendingPathComponent("StackBoardLiveTests-\(UUID().uuidString)", isDirectory: true)
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

    func testTheSchemaIsTheGoldenFixture() throws {
        let (cli, config) = try setting()
        let schema = try run(cli, config, ["widgets", "schema", "--json"])
        XCTAssertEqual(schema.status, 0, schema.stderr)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DevmachineCoreTests/Fixtures/widget-contract-1.5.json")
        XCTAssertEqual(try canonical(Data(schema.stdout.utf8)), try canonical(Data(contentsOf: fixture)))
    }

    private func canonical(_ json: Data) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]),
            options: [.sortedKeys, .fragmentsAllowed])
    }

    func testTheCLIReordersAnAppWrittenStackAndKeepsInlineEntries() throws {
        let (cli, config) = try setting()
        let url = BoardFiles.url(configDirectory: config, surface: DefaultStackBoard.contextSidebar)
        let store = StackBoardStore(
            fileURL: url, surface: DefaultStackBoard.contextSidebar,
            makeDefault: { DefaultStackBoard.make(surface: DefaultStackBoard.contextSidebar) })
        store.load()
        let inline = """
              - id: here
                title: Here
                source: {kind: command, run: ls, args: ["{{context.path}}"], every: 30s}
                view: {kind: text}
                size: medium

            """
        try Data((String(contentsOf: url, encoding: .utf8) + inline).utf8).write(to: url, options: .atomic)

        let validate = try run(cli, config, ["widgets", "validate", url.path])
        XCTAssertEqual(validate.status, 0, validate.stdout + validate.stderr)
        let move = try run(cli, config, ["widgets", "move", "links", "--before", "shortcuts", "--board", "context-sidebar"])
        XCTAssertEqual(move.status, 0, move.stderr)
        let remove = try run(cli, config, ["widgets", "remove", "todo", "--board", "context-sidebar"])
        XCTAssertEqual(remove.status, 0, remove.stderr)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains(inline.trimmingCharacters(in: .newlines)), text)
        store.load()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.board?.entries.map(\.id), [
            "links", "shortcuts", "publish-port", "monitors", "shells", "sub-agents", "pull-requests", "here",
        ])

        let framed = text.replacingOccurrences(
            of: "    size: medium", with: "    size: medium\n    frame: {x: 0, y: 0, w: 1, h: 1}")
        try Data(framed.utf8).write(to: url, options: .atomic)
        let refused = try run(cli, config, ["widgets", "validate", url.path])
        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue((refused.stdout + refused.stderr).contains("has no frame"), refused.stdout + refused.stderr)
    }
}
