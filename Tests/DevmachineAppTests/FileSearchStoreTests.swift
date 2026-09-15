import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class FileSearchStoreTests: XCTestCase {
    func testTypingFiltersWithoutAskingTheHostAgain() {
        let store = FileSearchStore()
        store.acceptForTesting(["src/AppModel.swift", "README.md", "src/Setup.swift"])

        store.query = "apmd"
        XCTAssertEqual(store.hits.first?.path, "src/AppModel.swift")

        store.query = "read"
        XCTAssertEqual(store.hits.first?.path, "README.md")
    }

    func testAnEmptyQueryShowsTheListAsItIs() {
        let store = FileSearchStore()
        store.acceptForTesting(["a.swift", "b.swift"])
        XCTAssertEqual(store.hits.count, 2)
        XCTAssertEqual(store.fileCount, 2)
    }

    func testClearingDropsTheQueryAndTheResults() {
        let store = FileSearchStore()
        store.acceptForTesting(["a.swift"])
        store.query = "a"
        store.clear()

        XCTAssertTrue(store.query.isEmpty)
        XCTAssertTrue(store.hits.isEmpty)
    }
}
