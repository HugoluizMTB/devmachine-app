import XCTest
@testable import DevmachineCore

final class AppLoggerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("applogger-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func contents(_ name: String = "app.log") -> String {
        (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    func testLineHasTimestampLevelCategoryAndMessage() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        XCTAssertEqual(
            AppLogger.line(date: date, level: .info, category: "cli", message: "devmachine version exit 0"),
            "2026-09-21T14:13:20.250Z INFO  [cli] devmachine version exit 0\n")
        XCTAssertEqual(
            AppLogger.line(date: date, level: .error, category: "cli", message: "failed\nfirst\nsecond"),
            "2026-09-21T14:13:20.250Z ERROR [cli] failed\n    | first\n    | second\n")
    }

    func testWritesFileAndFolderReadableOnlyByThisAccount() throws {
        let logger = AppLogger(directory: directory)
        logger.info("app", "started")
        logger.flush()
        XCTAssertTrue(contents().contains("INFO  [app] started"))
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        let file = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("app.log").path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testMessagesAreRedacted() {
        let logger = AppLogger(directory: directory)
        logger.error("cli", "failed with token=fake-secret-value")
        logger.flush()
        XCTAssertFalse(contents().contains("fake-secret-value"))
        XCTAssertTrue(contents().contains("token=***"))
    }

    func testDebugLinesOnlyWhenDebugIsOn() {
        let logger = AppLogger(directory: directory)
        logger.debug("ui", "hidden")
        logger.level = .debug
        logger.debug("ui", "shown")
        logger.flush()
        XCTAssertFalse(contents().contains("hidden"))
        XCTAssertTrue(contents().contains("DEBUG [ui] shown"))
    }

    func testTheSameLineIsWrittenOnceInTheRepeatWindow() {
        let logger = AppLogger(directory: directory)
        logger.error("widgets", "widget clock: failed")
        logger.error("widgets", "widget usage: failed")
        logger.error("widgets", "widget clock: failed")
        logger.flush()
        XCTAssertEqual(contents().components(separatedBy: "widget clock: failed").count - 1, 1)
        XCTAssertTrue(contents().contains("widget usage: failed"))
        let noWindow = AppLogger(directory: directory, repeatWindow: 0)
        noWindow.error("widgets", "widget clock: failed")
        noWindow.error("widgets", "widget clock: failed")
        noWindow.flush()
        XCTAssertEqual(contents().components(separatedBy: "widget clock: failed").count - 1, 3)
    }

    func testRotationKeepsAtMostThreeOldFiles() throws {
        let logger = AppLogger(directory: directory, maxBytes: 200)
        for index in 0..<40 {
            logger.info("test", "line number \(index) " + String(repeating: "x", count: 40))
        }
        logger.flush()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(names, ["app.log", "app.log.1", "app.log.2", "app.log.3"])
        for name in names {
            let size = try FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path)[.size] as? Int ?? 0
            XCTAssertLessThanOrEqual(size, 200, name)
        }
        XCTAssertTrue(contents().contains("line number 39"))
        XCTAssertFalse(contents("app.log.3").contains("line number 0 "))
    }

    func testWriteFailureIsSilent() throws {
        try FileManager.default.createDirectory(
            at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: directory)
        let logger = AppLogger(directory: directory)
        logger.error("app", "nowhere to go")
        logger.flush()
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isFolder))
        XCTAssertFalse(isFolder.boolValue)
    }

    func testPolledReadSuccessIsLoggedOnlyInDebug() {
        let logger = AppLogger(directory: directory)
        logger.cliCall(CLICall(arguments: ["--format", "json", "sessions"], exitCode: 0, duration: 0.2, stderr: ""))
        logger.flush()
        XCTAssertFalse(contents().contains("sessions"))
        logger.level = .debug
        logger.cliCall(CLICall(arguments: ["--format", "json", "sessions"], exitCode: 0, duration: 0.2, stderr: ""))
        logger.flush()
        XCTAssertTrue(contents().contains("DEBUG [cli] devmachine --format json sessions: exit 0"))
    }

    func testPolledReadLogsFailureOnceAndTheRecovery() {
        let logger = AppLogger(directory: directory)
        let failed = CLICall(arguments: ["machines", "list"], exitCode: 1, duration: 0.1, stderr: "boom")
        logger.cliCall(failed)
        logger.cliCall(failed)
        logger.cliCall(CLICall(arguments: ["machines", "list"], exitCode: 0, duration: 0.1, stderr: ""))
        logger.cliCall(CLICall(arguments: ["machines", "list"], exitCode: 0, duration: 0.1, stderr: ""))
        logger.flush()
        let text = contents()
        XCTAssertEqual(text.components(separatedBy: "ERROR [cli] devmachine machines list: exit 1").count - 1, 1, text)
        XCTAssertEqual(text.components(separatedBy: "works again").count - 1, 1, text)
    }

    func testActionSuccessIsLogged() {
        let logger = AppLogger(directory: directory)
        logger.cliCall(CLICall(arguments: ["machines", "add", "main"], exitCode: 0, duration: 1.5, stderr: ""))
        logger.flush()
        XCTAssertTrue(contents().contains("INFO  [cli] devmachine machines add main: exit 0 in 1.50s"), contents())
    }
}
