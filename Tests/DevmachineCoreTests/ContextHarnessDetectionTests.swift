import XCTest
@testable import DevmachineCore

final class ContextHarnessDetectionTests: XCTestCase {
    private func roots() -> (ContextRoots, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let roots = ContextRoots(home: base)
        return (roots, base)
    }

    private func touch(_ url: URL, contents: String = "{}") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testPaneCommandNamesTheHarnessDirectly() throws {
        let (roots, _) = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let slug = ClaudeHarness.slug(for: project)
        try touch(roots.claudeProjectsDir.appendingPathComponent(slug).appendingPathComponent("a.jsonl"))

        let result = ContextHarnessDetection.detect(project: project, paneCommand: "claude", roots: roots)
        XCTAssertEqual(result?.harness, .claude)
    }

    func testFallsBackToTheMostRecentlyModifiedTranscriptAcrossHarnesses() throws {
        let (roots, _) = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        let claudeSlug = ClaudeHarness.slug(for: project)
        let piSlug = PiHarness.slug(for: project)
        let claudeFile = roots.claudeProjectsDir.appendingPathComponent(claudeSlug).appendingPathComponent("a.jsonl")
        let piFile = roots.piSessionsDir.appendingPathComponent(piSlug).appendingPathComponent("b.jsonl")
        try touch(claudeFile)
        Thread.sleep(forTimeInterval: 0.05)
        try touch(piFile)

        let result = ContextHarnessDetection.detect(project: project, paneCommand: nil, roots: roots)
        XCTAssertEqual(result?.harness, .pi)
    }

    func testAPaneCommandNamesAHarnessOnlyByItsExactProgramName() {
        let names: [HarnessID: Set<String>] = [.pi: ["pi"], .antigravity: ["agy"], .cline: ["cline", ".cline"]]
        XCTAssertEqual(ContextHarnessDetection.harnesses(running: "pi", processNames: names), [.pi])
        XCTAssertEqual(ContextHarnessDetection.harnesses(running: "/usr/local/bin/pi --resume", processNames: names), [.pi])
        XCTAssertEqual(ContextHarnessDetection.harnesses(running: "agy", processNames: names), [.antigravity])
        XCTAssertEqual(ContextHarnessDetection.harnesses(running: ".cline", processNames: names), [.cline])
        for other in ["pip", "spinner", "python", "node", "zsh", "-zsh", ""] {
            XCTAssertEqual(ContextHarnessDetection.harnesses(running: other, processNames: names), [], other)
        }
    }

    func testWithoutNamesAHarnessIsKnownByItsId() {
        XCTAssertEqual(ContextHarnessDetection.harnesses(running: "opencode", processNames: [:]), [.opencode])
        XCTAssertEqual(ContextHarnessDetection.harnesses(running: "pip", processNames: [:]), [])
    }

    func testAPaneRunningPipIsNotTakenForPi() throws {
        let (roots, _) = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        try touch(roots.piSessionsDir.appendingPathComponent(PiHarness.slug(for: project)).appendingPathComponent("b.jsonl"))
        Thread.sleep(forTimeInterval: 0.05)
        try touch(roots.claudeProjectsDir.appendingPathComponent(ClaudeHarness.slug(for: project)).appendingPathComponent("a.jsonl"))

        let result = ContextHarnessDetection.detect(project: project, paneCommand: "pip", roots: roots)
        XCTAssertEqual(result?.harness, .claude)
    }

    func testAHarnessSeenInTheSessionWinsOverANewerTranscript() throws {
        let (roots, _) = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        try touch(roots.piSessionsDir.appendingPathComponent(PiHarness.slug(for: project)).appendingPathComponent("b.jsonl"))
        Thread.sleep(forTimeInterval: 0.05)
        try touch(roots.claudeProjectsDir.appendingPathComponent(ClaudeHarness.slug(for: project)).appendingPathComponent("a.jsonl"))

        let result = ContextHarnessDetection.detect(project: project, paneCommand: nil, harnesses: [.pi], roots: roots)
        XCTAssertEqual(result?.harness, .pi)
    }

    func testFallbackConsidersEveryHarness() throws {
        let (roots, _) = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/dash")
        try touch(roots.claudeProjectsDir.appendingPathComponent(ClaudeHarness.slug(for: project)).appendingPathComponent("a.jsonl"))
        Thread.sleep(forTimeInterval: 0.05)
        let session = roots.kimiHome.appendingPathComponent("sessions")
            .appendingPathComponent(KimiHarness.workdirKey(for: project.path))
            .appendingPathComponent("session_1/agents/main/wire.jsonl")
        try touch(session)

        let result = ContextHarnessDetection.detect(project: project, paneCommand: nil, roots: roots)
        XCTAssertEqual(result?.harness, .kimi)
    }

    func testNoTranscriptsAnywhereReturnsNil() {
        let (roots, _) = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/nowhere")
        let result = ContextHarnessDetection.detect(project: project, paneCommand: nil, roots: roots)
        XCTAssertNil(result)
    }
}
