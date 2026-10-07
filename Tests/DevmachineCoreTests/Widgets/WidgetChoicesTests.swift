import XCTest
@testable import DevmachineCore

final class WidgetChoicesTests: XCTestCase {
    private let options = [
        ChoiceOption(id: "main", label: "main"), ChoiceOption(id: "here", label: "here"),
        ChoiceOption(id: "build", label: "build"),
    ]
    private var many: ChoiceInput {
        ChoiceInput(
            name: "machines",
            input: CatalogInput(type: "choice", defaultValue: nil, summary: "Machines to show.", from: "machines", many: true))!
    }
    private var one: ChoiceInput {
        ChoiceInput(name: "harness", input: CatalogInput(type: "choice", defaultValue: nil, summary: "", from: "harnesses"))!
    }

    func testOnlyAChoiceWithAKnownSourceIsAChoice() {
        XCTAssertNil(ChoiceInput(name: "x", input: CatalogInput(type: "string", defaultValue: nil, summary: "")))
        XCTAssertNil(ChoiceInput(name: "x", input: CatalogInput(type: "choice", defaultValue: nil, summary: "", from: "planets")))
        XCTAssertEqual(many.source, .machines)
    }

    func testAllListsAWidgetsChoicesByName() {
        let widget = CatalogWidget(
            name: "acme/w",
            inputs: [
                "b": CatalogInput(type: "choice", defaultValue: nil, summary: "", from: "workspaces"),
                "a": CatalogInput(type: "choice", defaultValue: nil, summary: "", from: "machines", many: true),
                "c": CatalogInput(type: "string", defaultValue: nil, summary: ""),
            ],
            source: CatalogSource(name: "app/machines", every: "60s"), viewKind: "app.machines", sizes: [],
            defaultSize: "")
        XCTAssertEqual(ChoiceInput.all(of: widget).map(\.name), ["a", "b"])
    }

    func testTheMenuTitleReadsTheSummary() {
        XCTAssertEqual(many.menuTitle, "Choose machines to show…")
        XCTAssertEqual(one.menuTitle, "Choose harness…")
        let published = ChoiceInput(
            name: "machines",
            input: CatalogInput(
                type: "choice", defaultValue: nil, summary: "Which machines to show; none picked shows them all.",
                from: "machines", many: true))!
        XCTAssertEqual(published.menuTitle, "Choose which machines to show…")
    }

    func testNoValueMeansAllForMany() {
        let selection = ChoiceSelection(input: many, current: nil, options: options)
        XCTAssertTrue(selection.isAll)
        XCTAssertTrue(selection.isChosen("main"))
        XCTAssertNil(selection.value)
    }

    func testUntickingOneOfAllKeepsTheOthers() {
        var selection = ChoiceSelection(input: many, current: nil, options: options)
        selection.toggle("here")
        XCTAssertEqual(selection.value, .list(["main", "build"]))
        XCTAssertFalse(selection.isChosen("here"))
    }

    func testTickingEveryOptionMeansAllAndWritesNothing() {
        var selection = ChoiceSelection(input: many, current: .list(["main", "here"]), options: options)
        selection.toggle("build")
        XCTAssertTrue(selection.isAll)
        XCTAssertNil(selection.value)
    }

    func testUntickingTheLastMeansAll() {
        var selection = ChoiceSelection(input: many, current: .list(["main"]), options: options)
        selection.toggle("main")
        XCTAssertTrue(selection.isAll)
        XCTAssertNil(selection.value)
    }

    func testAChosenNameThatIsGoneStaysVisible() {
        let selection = ChoiceSelection(input: many, current: .list(["old", "main"]), options: options)
        XCTAssertEqual(selection.options.last, ChoiceOption(id: "old", label: "old (not found)", isMissing: true))
        XCTAssertTrue(selection.isChosen("old"))
        XCTAssertEqual(selection.value, .list(["main", "old"]))
    }

    func testOneValueIsAPick() {
        var selection = ChoiceSelection(input: one, current: nil, options: options)
        XCTAssertNil(selection.value)
        XCTAssertFalse(selection.isAll)
        selection.pick("here")
        XCTAssertEqual(selection.value, .string("here"))
        XCTAssertTrue(selection.isChosen("here"))
    }

    func testAListDefaultIsTheStartingChoice() {
        let input = ChoiceInput(
            name: "machines",
            input: CatalogInput(type: "choice", defaultValue: .list(["main"]), summary: "", from: "machines", many: true))!
        XCTAssertEqual(ChoiceSelection(input: input, current: nil, options: options).chosen, ["main"])
    }
}
