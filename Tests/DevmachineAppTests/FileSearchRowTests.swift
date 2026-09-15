import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

final class FileSearchRowTests: XCTestCase {
    func testTheFileNameIsSeparatedFromTheFolder() {
        let parts = FileSearchRow.split(path: "src/app/Model.swift", matches: [])
        XCTAssertEqual(parts.name.map(\.text).joined(), "Model.swift")
        XCTAssertEqual(parts.folder.map(\.text).joined(), "src/app/")
    }

    func testMatchedLettersBecomeTheirOwnRuns() {
        // "Mo" of Model matched.
        let path = "src/Model.swift"
        let matches = [4, 5]
        let parts = FileSearchRow.split(path: path, matches: matches)

        XCTAssertEqual(parts.name.first, FileSearchRow.Run(text: "Mo", matched: true))
        XCTAssertEqual(parts.name.dropFirst().first?.matched, false)
        XCTAssertTrue(parts.folder.allSatisfy { !$0.matched })
    }

    func testAPathWithoutAFolderIsAllName() {
        let parts = FileSearchRow.split(path: "README.md", matches: [])
        XCTAssertEqual(parts.name.map(\.text).joined(), "README.md")
        XCTAssertTrue(parts.folder.isEmpty)
    }

    func testTheRunsAlwaysRebuildThePath() {
        let hit = FileSearch.rank(["src/app/AppModel.swift"], query: "apmd").first!
        let parts = FileSearchRow.split(path: hit.path, matches: hit.matches)
        XCTAssertEqual(
            parts.folder.map(\.text).joined() + parts.name.map(\.text).joined(), hit.path)
    }
}
