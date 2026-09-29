import XCTest
@testable import DevmachineCore

final class ContextHarnessDetectionTests: XCTestCase {
    private func roots() -> (ContextRoots, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let roots = ContextRoots(
            claudeProjectsDir: base.appendingPathComponent("claude"),
            codexSessionsDir: base.appendingPathComponent("codex"),
            piSessionsDir: base.appendingPathComponent("pi")
        )
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

    func testNoTranscriptsAnywhereReturnsNil() {
        let (roots, _) = roots()
        let project = URL(fileURLWithPath: "/Users/alice/dev/nowhere")
        let result = ContextHarnessDetection.detect(project: project, paneCommand: nil, roots: roots)
        XCTAssertNil(result)
    }
}
