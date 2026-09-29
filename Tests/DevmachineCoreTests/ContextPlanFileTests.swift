import XCTest
@testable import DevmachineCore

final class ContextPlanFileTests: XCTestCase {
    private func tempFile(_ contents: String, name: String = "plan.md") -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testParsesCheckedAndUncheckedItems() {
        let url = tempFile("""
        # Plan

        - [ ] write the tests
        - [x] read the spec
        """)
        let plan = ContextPlanFile.parse(url)
        XCTAssertEqual(plan?.done, 1)
        XCTAssertEqual(plan?.total, 2)
        XCTAssertEqual(plan?.items.map(\.text), ["write the tests", "read the spec"])
        XCTAssertEqual(plan?.source, "file")
    }

    func testFileWithNoChecklistItemsReturnsNil() {
        let url = tempFile("# Just a heading\n\nSome prose.")
        XCTAssertNil(ContextPlanFile.parse(url))
    }

    func testMostRecentPrefersTouchedMarkdownOverSpecsDirectory() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let specsDir = project.appendingPathComponent("docs/superpowers/specs")
        try FileManager.default.createDirectory(at: specsDir, withIntermediateDirectories: true)
        try "- [ ] old plan item".write(
            to: specsDir.appendingPathComponent("old.md"), atomically: true, encoding: .utf8
        )
        Thread.sleep(forTimeInterval: 0.05)
        let touched = project.appendingPathComponent("NOTES.md")
        try "- [ ] fresh plan item".write(to: touched, atomically: true, encoding: .utf8)

        let plan = ContextPlanFile.mostRecent(project: project, touchedMarkdown: [touched.path])
        XCTAssertEqual(plan?.items.first?.text, "fresh plan item")
    }
}
