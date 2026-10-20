import XCTest
@testable import DevmachineCore

final class LogBundleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("logbundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
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
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            .filter { !$0.hasSuffix("/") }.sorted()
    }

    func testZipHoldsEveryLogAndAbout() throws {
        try write("app", to: "app-logs/app.log")
        try write("app1", to: "app-logs/app.log.1")
        try write("pane", to: "app-logs/terminal.log")
        try write("ignored", to: "app-logs/notes.txt")
        try write("cli", to: "config/logs/devmachine.log")
        try write("cli2", to: "config/logs/devmachine.log.2")
        try write("history", to: "config/history.log")
        let sources = LogBundle.Sources(
            appLogDirectory: root.appendingPathComponent("app-logs"),
            cliConfigDirectory: root.appendingPathComponent("config"))
        let about = LogBundle.about(appVersion: "0.8.0", cliVersion: "0.16.0", macOS: "15.6.1", arch: "arm64")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let zip = try LogBundle.write(sources: sources, about: about, to: root.appendingPathComponent("Desktop"), date: date,
            timeZone: TimeZone(identifier: "UTC")!)

        XCTAssertEqual(zip.lastPathComponent, "devmachine-logs-2026-09-21-141320.zip")
        XCTAssertEqual(try entries(of: zip), [
            "devmachine-logs-2026-09-21-141320/about.txt",
            "devmachine-logs-2026-09-21-141320/app.log",
            "devmachine-logs-2026-09-21-141320/app.log.1",
            "devmachine-logs-2026-09-21-141320/devmachine.log",
            "devmachine-logs-2026-09-21-141320/devmachine.log.2",
            "devmachine-logs-2026-09-21-141320/history.log",
            "devmachine-logs-2026-09-21-141320/terminal.log",
        ])
    }

    func testMissingCLIFolderStillWritesTheAppLogs() throws {
        try write("app", to: "app-logs/app.log")
        let sources = LogBundle.Sources(appLogDirectory: root.appendingPathComponent("app-logs"), cliConfigDirectory: nil)
        let zip = try LogBundle.write(
            sources: sources, about: "about", to: root, date: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(try entries(of: zip).map { ($0 as NSString).lastPathComponent }, ["about.txt", "app.log"])
    }

    func testAboutNamesTheVersions() {
        let about = LogBundle.about(appVersion: "0.8.0", cliVersion: "unknown", macOS: "15.6.1", arch: "arm64")
        XCTAssertTrue(about.contains("App: 0.8.0"))
        XCTAssertTrue(about.contains("CLI: unknown"))
        XCTAssertTrue(about.contains("macOS: 15.6.1 (arm64)"))
    }

    func testFilesForTheMenu() {
        let config = URL(fileURLWithPath: "/Users/alice/.config/devmachine")
        XCTAssertEqual(LogBundle.cliLog(in: config).path, "/Users/alice/.config/devmachine/logs/devmachine.log")
        XCTAssertEqual(LogBundle.history(in: config).path, "/Users/alice/.config/devmachine/history.log")
    }
}
