import XCTest
@testable import DevmachineCore

final class ClaudeTaskListTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func task(_ id: String, _ subject: String, _ status: String, in dir: URL) throws {
        let json = #"{"id":"\#(id)","subject":"\#(subject)","description":"d","status":"\#(status)","blocks":[],"blockedBy":[]}"#
        try json.write(to: dir.appendingPathComponent("\(id).json"), atomically: true, encoding: .utf8)
    }

    func testOrdersByNumericIDAndMapsStatuses() throws {
        let dir = try directory()
        try task("2", "second", "in_progress", in: dir)
        try task("10", "tenth", "completed", in: dir)
        try task("1", "first", "pending", in: dir)

        XCTAssertEqual(ClaudeTaskList.read(directory: dir), [
            ContextEngineResult.PlanItem(text: "first", state: "pending"),
            ContextEngineResult.PlanItem(text: "second", state: "active"),
            ContextEngineResult.PlanItem(text: "tenth", state: "done"),
        ])
    }

    func testSkipsFilesThatFailToDecode() throws {
        let dir = try directory()
        try task("1", "first", "pending", in: dir)
        try "not json".write(to: dir.appendingPathComponent("2.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(ClaudeTaskList.read(directory: dir).map(\.text), ["first"])
    }

    func testMissingDirectoryIsEmpty() throws {
        XCTAssertEqual(ClaudeTaskList.read(directory: try directory().appendingPathComponent("none")), [])
    }

    func testConfigDirEnvironmentWinsOverTheProjectsParent() {
        let projects = URL(fileURLWithPath: "/Users/alice/.claude/projects")
        XCTAssertEqual(
            ClaudeTaskList.directory(sessionID: "s1", projectsDir: projects, environment: [:]).path,
            "/Users/alice/.claude/tasks/s1")
        XCTAssertEqual(
            ClaudeTaskList.directory(sessionID: "s1", projectsDir: projects,
                                     environment: ["CLAUDE_CONFIG_DIR": "/Users/alice/alt"]).path,
            "/Users/alice/alt/tasks/s1")
    }
}
