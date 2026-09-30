import XCTest
@testable import DevmachineCore

final class DetachedProcessTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("detached-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testTheHelperLeadsItsOwnSessionSoItOutlivesTheApp() throws {
        let out = folder.appendingPathComponent("group")
        let pid = try DetachedProcess.spawn(
            executable: "/bin/sh", arguments: ["-c", "ps -o pgid= -p $$ > \"$0\"", out.path])

        let group = try waitForText(at: out)
        XCTAssertEqual(Int32(group), pid)
        XCTAssertNotEqual(Int32(group), getpgrp())
    }

    func testTheHelperGetsNoneOfTheAppsOpenFiles() throws {
        let held = open(folder.appendingPathComponent("held").path, O_CREAT | O_WRONLY, 0o600)
        XCTAssertGreaterThan(held, 2)
        defer { close(held) }
        let out = folder.appendingPathComponent("fd")

        _ = try DetachedProcess.spawn(
            executable: "/bin/sh",
            arguments: ["-c", "if [ -e /dev/fd/$1 ]; then echo open; else echo closed; fi > \"$0\"", out.path, "\(held)"])

        XCTAssertEqual(try waitForText(at: out), "closed")
    }

    func testAMissingProgramThrows() {
        XCTAssertThrowsError(try DetachedProcess.spawn(executable: "/nonexistent/helper", arguments: []))
    }

    private func waitForText(at url: URL) throws -> String {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: url, encoding: .utf8), text.hasSuffix("\n") {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw XCTSkip("the helper wrote nothing to \(url.lastPathComponent)")
    }
}
