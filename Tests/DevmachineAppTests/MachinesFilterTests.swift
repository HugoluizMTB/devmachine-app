import XCTest
import DevmachineCore
import HarnessUsageKit
@testable import DevmachineApp

final class MachinesFilterTests: XCTestCase {
    private let machines = [
        StatsMachine(name: "main", firstAddress: nil), StatsMachine(name: "here", firstAddress: nil),
        StatsMachine(name: "build", firstAddress: nil),
    ]

    func testNoChoiceShowsEveryMachine() {
        XCTAssertEqual(MachinesFilter.shown(machines, chosen: []).map(\.name), ["main", "here", "build"])
    }

    func testAChoiceKeepsTheStoresOrder() {
        XCTAssertEqual(MachinesFilter.shown(machines, chosen: ["build", "main"]).map(\.name), ["main", "build"])
    }

    func testANameThatIsGoneShowsNothingForIt() {
        XCTAssertEqual(MachinesFilter.shown(machines, chosen: ["old"]).map(\.name), [])
        XCTAssertEqual(MachinesFilter.shown(names: ["main", "here"], chosen: ["here"]), ["here"])
    }

    func testUsageTakesTheChosenHarnessOrTheFirst() {
        let states = [HarnessUsageState(harnessID: "codex"), HarnessUsageState(harnessID: "claude")]
        XCTAssertEqual(UsageHarnessChoice.harness("claude", states: states), "claude")
        XCTAssertEqual(UsageHarnessChoice.harness("", states: states), "codex")
        XCTAssertEqual(UsageHarnessChoice.harness("", states: []), "")
    }

    func testTheDemoCatalogDeclaresTheChoices() {
        let usage = DemoData.widgetCatalog.widget(named: "devmachine-app/usage")
        XCTAssertEqual(usage?.inputs["harness"]?.from, "harnesses")
        let machines = DemoData.widgetCatalog.widget(named: "devmachine-app/machines")
        XCTAssertEqual(machines?.inputs["machines"]?.many, true)
    }
}
