import XCTest
@testable import DevmachineCore

final class RelaunchCommandTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("relaunch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testWaitsForThisProcessThenOpensTheApp() {
        let command = RelaunchCommand(appPath: "/Applications/Devmachine.app", processID: 4242)
        XCTAssertEqual(command.executable, "/bin/sh")
        XCTAssertEqual(command.arguments.count, 5)
        XCTAssertEqual(command.arguments[0], "-c")
        XCTAssertTrue(command.arguments[1].contains("kill -0"))
        XCTAssertEqual(command.arguments[2], "/Applications/Devmachine.app")
        XCTAssertEqual(command.arguments[3], "4242")
        XCTAssertEqual(command.arguments[4], "/usr/bin/open")
    }

    func testThePathNeverEntersTheScriptText() {
        let path = "/Applications/Dev \"$(rm -rf ~)\".app"
        let command = RelaunchCommand(appPath: path, processID: 1)
        XCTAssertFalse(command.arguments[1].contains(path))
    }

    func testNeverAsksForASecondCopy() {
        let command = RelaunchCommand(appPath: "/Applications/Devmachine.app", processID: 4242)
        XCTAssertFalse(command.arguments[1].contains("-n"))
    }

    func testOpensTheAppOnceTheProcessHasQuit() throws {
        let exited = Process()
        exited.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try exited.run()
        exited.waitUntilExit()

        let result = try run(RelaunchCommand(
            appPath: "/Applications/Devmachine.app", processID: exited.processIdentifier,
            attempts: 5, settle: 0, opener: recorder()))

        XCTAssertEqual(result, 0)
        XCTAssertEqual(try recorded(), "/Applications/Devmachine.app\n")
    }

    func testOpensNothingWhileTheOldCopyIsStillRunning() throws {
        let result = try run(RelaunchCommand(
            appPath: "/Applications/Devmachine.app", processID: ProcessInfo.processInfo.processIdentifier,
            attempts: 2, settle: 0, opener: recorder()))

        XCTAssertNotEqual(result, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("opened").path))
    }

    private func recorder() throws -> String {
        let script = folder.appendingPathComponent("open")
        try "#!/bin/sh\necho \"$@\" >> \"\(folder.path)/opened\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    private func recorded() throws -> String {
        try String(contentsOf: folder.appendingPathComponent("opened"), encoding: .utf8)
    }

    private func run(_ command: RelaunchCommand) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
