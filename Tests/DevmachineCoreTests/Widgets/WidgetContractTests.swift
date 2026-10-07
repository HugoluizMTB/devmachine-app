import XCTest
@testable import DevmachineCore

final class WidgetContractTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widget-contract-1.0.json")
        return try Data(contentsOf: url)
    }

    func testTheGoldenContractIsTheOneThisAppImplements() throws {
        let decoded = try JSONDecoder().decode(WidgetContract.self, from: fixture())
        XCTAssertEqual(decoded, WidgetContract.engine10)
    }

    func testPresetsAreCellsOfTheUnit() {
        let contract = WidgetContract.engine10
        XCTAssertEqual(contract.unit, 80)
        XCTAssertEqual(contract.snap, 8)
        XCTAssertEqual(contract.presetCells("wide")?.columns, 8)
        XCTAssertEqual(contract.presetCells("wide")?.rows, 2)
        XCTAssertNil(contract.presetCells("huge"))
        XCTAssertEqual(WidgetContract.presetOrder, ["small", "medium", "large", "wide", "tall"])
    }

    func testEveryAppProviderAsksForAtLeastFiveSeconds() {
        for name in ["app/clock", "app/summary", "app/machines", "app/harness-usage"] {
            XCTAssertEqual(WidgetContract.engine10.minimumInterval(for: name), 5, name)
        }
        XCTAssertNil(WidgetContract.engine10.minimumInterval(for: "command"))
    }

    func testAViewAcceptsOnlyItsOwnProvider() {
        XCTAssertTrue(WidgetContract.engine10.view("app.clock", accepts: "app/clock"))
        XCTAssertFalse(WidgetContract.engine10.view("app.clock", accepts: "app/summary"))
        XCTAssertFalse(WidgetContract.engine10.view("gauge", accepts: "app/clock"))
    }

    func testGoDurations() {
        XCTAssertEqual(GoDuration.seconds("60s"), 60)
        XCTAssertEqual(GoDuration.seconds("1m30s"), 90)
        XCTAssertEqual(GoDuration.seconds("500ms"), 0.5)
        XCTAssertEqual(GoDuration.seconds("1h"), 3600)
        XCTAssertEqual(GoDuration.seconds("0"), 0)
        XCTAssertNil(GoDuration.seconds("5"))
        XCTAssertNil(GoDuration.seconds(""))
        XCTAssertNil(GoDuration.seconds("abc"))
    }
}
