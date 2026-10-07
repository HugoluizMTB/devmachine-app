import XCTest
@testable import DevmachineCore

final class WidgetContractTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widget-contract-1.1.json")
        return try Data(contentsOf: url)
    }

    func testTheGoldenContractIsTheOneThisAppImplements() throws {
        let decoded = try JSONDecoder().decode(WidgetContract.self, from: fixture())
        XCTAssertEqual(decoded, WidgetContract.engine11)
        XCTAssertEqual(WidgetContract.current, WidgetContract.engine11)
        XCTAssertEqual(WidgetContract.current.engine, "1.1")
    }

    func testPresetsAreCellsOfTheUnit() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.unit, 80)
        XCTAssertEqual(contract.snap, 8)
        XCTAssertEqual(contract.presetCells("wide")?.columns, 8)
        XCTAssertEqual(contract.presetCells("wide")?.rows, 2)
        XCTAssertNil(contract.presetCells("huge"))
        XCTAssertEqual(WidgetContract.presetOrder, ["small", "medium", "large", "wide", "tall"])
    }

    func testEveryAppProviderAsksForAtLeastFiveSeconds() {
        for name in ["app/clock", "app/summary", "app/machines", "app/harness-usage"] {
            XCTAssertEqual(WidgetContract.current.minimumInterval(for: name), 5, name)
        }
        XCTAssertNil(WidgetContract.current.minimumInterval(for: "command"))
    }

    func testSourceMinimumsComeFromTheContract() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.minimumInterval(forSource: "command"), 5)
        XCTAssertEqual(contract.minimumInterval(forSource: "url"), 5)
        XCTAssertEqual(contract.minimumInterval(forSource: "session"), 2)
        XCTAssertEqual(contract.minimumInterval(forSource: "prompt"), 900)
        XCTAssertNil(contract.minimumInterval(forSource: "provider"))
    }

    func testOnlyCommandPromptAndSessionWaitForApproval() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.sourceKinds.filter(contract.needsApproval), ["command", "prompt", "session"])
    }

    func testAViewAcceptsATokenOrAWholeKind() {
        let contract = WidgetContract.current
        XCTAssertTrue(contract.view("app.clock", accepts: "app/clock"))
        XCTAssertFalse(contract.view("app.clock", accepts: "app/summary"))
        XCTAssertTrue(contract.view("web", accepts: "status", sourceKind: "url"))
        XCTAssertFalse(contract.view("web", accepts: "text", sourceKind: "command"))
        XCTAssertTrue(contract.view("terminal", accepts: nil, sourceKind: "session"))
        XCTAssertFalse(contract.view("text", accepts: nil, sourceKind: "session"))
        XCTAssertTrue(contract.view("markdown", accepts: "text", sourceKind: "command"))
        XCTAssertFalse(contract.view("gauge", accepts: "text", sourceKind: "command"))
    }

    func testFieldSchemasCarryDefaultsAndLimits() {
        let command = WidgetContract.current.sources["command"]
        XCTAssertEqual(command?.fields["timeout"]?.defaultValue, .string("30s"))
        XCTAssertEqual(command?.fields["timeout"]?.max, .string("10m"))
        XCTAssertEqual(command?.fields["keep"]?.max, .int(2000))
        XCTAssertEqual(WidgetContract.current.views["web"]?.fields?["zoom"]?.min, .double(0.5))
        XCTAssertEqual(WidgetContract.current.views["list"]?.fields?["item"]?.fields?["title"]?.defaultValue, .string("{{item}}"))
    }

    func testGoDurations() {
        XCTAssertEqual(GoDuration.seconds("60s"), 60)
        XCTAssertEqual(GoDuration.seconds("1m30s"), 90)
        XCTAssertEqual(GoDuration.seconds("500ms"), 0.5)
        XCTAssertEqual(GoDuration.seconds("1h"), 3600)
        XCTAssertEqual(GoDuration.seconds("15m"), 900)
        XCTAssertEqual(GoDuration.seconds("0"), 0)
        XCTAssertNil(GoDuration.seconds("5"))
        XCTAssertNil(GoDuration.seconds(""))
        XCTAssertNil(GoDuration.seconds("abc"))
    }
}
