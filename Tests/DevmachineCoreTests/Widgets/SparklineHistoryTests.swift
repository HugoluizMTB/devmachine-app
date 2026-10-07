import XCTest
@testable import DevmachineCore

final class SparklineHistoryTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SparklineHistoryTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testKeepsTheLast120Points() {
        var history = SparklineHistory()
        for index in 0..<130 { history.append(Double(index), at: Date(timeIntervalSince1970: Double(index))) }
        XCTAssertEqual(history.points.count, 120)
        XCTAssertEqual(history.points.first?.value, 10)
        XCTAssertEqual(history.points.last?.value, 129)
    }

    func testIgnoresValuesThatAreNotNumbers() {
        var history = SparklineHistory()
        history.append(.nan, at: Date())
        history.append(.infinity, at: Date())
        XCTAssertTrue(history.points.isEmpty)
    }

    func testTheStoreNamesFilesBySurfaceAndID() throws {
        let store = SparklineHistoryStore(directory: folder)
        XCTAssertEqual(store.fileURL(surface: "home", id: "load").lastPathComponent, "home-load.json")
        var history = SparklineHistory()
        history.append(1.5, at: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(history, surface: "home", id: "load")
        XCTAssertEqual(store.load(surface: "home", id: "load"), history)
        XCTAssertEqual(store.load(surface: "home", id: "other"), SparklineHistory())
    }

    func testTheDefaultFolderIsInApplicationSupport() {
        XCTAssertTrue(SparklineHistoryStore.defaultDirectory.path.hasSuffix("Library/Application Support/Devmachine/widget-history"))
    }
}
