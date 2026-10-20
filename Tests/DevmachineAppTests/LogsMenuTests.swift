import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
private final class FakeLogWorkspace: LogWorkspace {
    var opened: [URL] = []
    var revealed: [[URL]] = []
    func open(_ url: URL) { opened.append(url) }
    func reveal(_ urls: [URL]) { revealed.append(urls) }
}

@MainActor
final class LogsMenuTests: XCTestCase {
    private var root: URL!
    private var workspace: FakeLogWorkspace!
    private var announced: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("logs-menu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        workspace = FakeLogWorkspace()
        announced = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private var config: URL { root.appendingPathComponent("config") }
    private var appLogs: URL { root.appendingPathComponent("Logs/Devmachine") }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func runner(configDirectory: URL?, cliLog: URL? = nil) -> LogActionRunner {
        let files = LogFiles(appLogDirectory: appLogs, resolve: {
            LogFiles.Resolved(
                configDirectory: configDirectory,
                cliLog: cliLog ?? configDirectory.map(LogBundle.cliLog(in:)))
        })
        return LogActionRunner(
            files: files, workspace: workspace, destination: root.appendingPathComponent("Desktop"),
            cliVersion: { "devmachine 0.16.0" }, announce: { [weak self] in self?.announced.append($0) })
    }

    func testTheMenuNamesAFileNotWrittenYet() {
        XCTAssertEqual(LogAction.openCLILog.title(), "Open CLI Log")
        XCTAssertEqual(LogAction.openCLILog.title(available: false), "Open CLI Log (none yet)")
        XCTAssertEqual(LogAction.allCases.map { $0.title() }, [
            "Open App Log", "Open CLI Log", "Open Command History", "Show Logs in Finder", "Save All Logs…",
        ])
    }

    func testAMissingCLILogOrHistoryOpensNothingAndSaysSo() async {
        let runner = runner(configDirectory: config)
        await runner.files.refresh()
        XCTAssertFalse(runner.files.isAvailable(.openCLILog))
        XCTAssertFalse(runner.files.isAvailable(.openHistory))

        let cli = await runner.perform(.openCLILog)
        let history = await runner.perform(.openHistory)

        XCTAssertNil(cli)
        XCTAssertNil(history)
        XCTAssertEqual(workspace.opened, [])
        XCTAssertEqual(announced, ["There is no CLI log yet", "There is no command history yet"])
    }

    func testNoCLIMeansNoCLILog() async {
        let runner = runner(configDirectory: nil)
        let opened = await runner.perform(.openCLILog)
        XCTAssertNil(opened)
        XCTAssertNil(runner.files.cliLog)
    }

    func testEachLogOpensInTheDefaultApp() async throws {
        try write("cli", to: config.appendingPathComponent("logs/devmachine.log"))
        try write("history", to: config.appendingPathComponent("history.log"))
        let runner = runner(configDirectory: config)

        await runner.perform(.openAppLog)
        await runner.perform(.openCLILog)
        await runner.perform(.openHistory)

        XCTAssertEqual(workspace.opened.map(\.path), [
            appLogs.appendingPathComponent("app.log").path,
            config.appendingPathComponent("logs/devmachine.log").path,
            config.appendingPathComponent("history.log").path,
        ])
        XCTAssertTrue(runner.files.isAvailable(.openCLILog))
    }

    func testTheCLIsOwnAnswerForItsLogWins() async throws {
        let elsewhere = root.appendingPathComponent("state/devmachine/devmachine.log")
        try write("cli", to: elsewhere)
        try write("cli old", to: elsewhere.appendingPathExtension("1"))
        let runner = runner(configDirectory: config, cliLog: elsewhere)

        await runner.perform(.openCLILog)
        let saved = await runner.perform(.saveAll)

        XCTAssertEqual(workspace.opened.map(\.path), [elsewhere.path])
        XCTAssertEqual(try entries(of: try XCTUnwrap(saved)), ["about.txt", "devmachine.log", "devmachine.log.1"])
    }

    func testShowInFinderSelectsTheAppLogAndTheCLILog() async throws {
        try write("cli", to: config.appendingPathComponent("logs/devmachine.log"))
        let runner = runner(configDirectory: config)

        await runner.perform(.showInFinder)

        XCTAssertEqual(workspace.revealed.first?.map(\.lastPathComponent), ["app.log", "devmachine.log"])
    }

    func testSaveAllWritesAZipOfEveryLogAndShowsIt() async throws {
        try write("app", to: appLogs.appendingPathComponent("app.log"))
        try write("app old", to: appLogs.appendingPathComponent("app.log.1"))
        try write("cli", to: config.appendingPathComponent("logs/devmachine.log"))
        try write("history", to: config.appendingPathComponent("history.log"))
        let runner = runner(configDirectory: config)

        let saved = await runner.perform(.saveAll)
        let zip = try XCTUnwrap(saved)

        XCTAssertEqual(zip.deletingLastPathComponent().path, root.appendingPathComponent("Desktop").path)
        XCTAssertTrue(zip.lastPathComponent.hasPrefix("devmachine-logs-"))
        XCTAssertEqual(workspace.revealed, [[zip]])
        XCTAssertEqual(try entries(of: zip), ["about.txt", "app.log", "app.log.1", "devmachine.log", "history.log"])
        XCTAssertEqual(announced, ["Saved \(zip.lastPathComponent) to Desktop"])
    }

    private func entries(of zip: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zip.path]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .filter { !$0.hasSuffix("/") }
            .map { String($0.split(separator: "/").last ?? "") }
            .sorted()
    }
}

@MainActor
final class LogPaletteTests: XCTestCase {
    func testThePaletteOffersTheLogsLikeTheHelpMenu() {
        var context = PaletteContext()
        let ids = CommandRegistry.commands(in: context).map(\.id).filter { $0.hasPrefix("action.logs.") }
        XCTAssertEqual(ids, ["action.logs.openAppLog", "action.logs.showInFinder", "action.logs.saveAll"])

        context.cliLogExists = true
        context.historyExists = true
        let commands = CommandRegistry.commands(in: context).filter { $0.id.hasPrefix("action.logs.") }
        XCTAssertEqual(commands.map(\.title), LogAction.allCases.map { $0.title() })
        XCTAssertEqual(commands.map(\.action), LogAction.allCases.map(PaletteAction.logs))
    }
}
