import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class FakeEditTarget: WidgetEditTarget {
    var editSurface = "home"
    var editFileName = "home.yml"
    var canEdit = true
    var editCatalog: WidgetCatalog?
    var entries: [String: EditableEntry] = [:]
    var applied: [(EntryEdit, String)] = []
    var added: [(InlineWidget, String, String)] = []

    func editableEntry(_ id: String) -> EditableEntry? { entries[id] }

    var refusal: String?

    func problem(with edit: EntryEdit, for id: String) -> String? { refusal }

    func apply(_ edit: EntryEdit, to id: String) -> Bool {
        if refusal != nil { return false }
        applied.append((edit, id))
        return true
    }

    func addInline(_ inline: InlineWidget, title: String, preset: String) -> String? {
        added.append((inline, title, preset))
        return "new"
    }
}

@MainActor
final class WidgetEditorModelTests: XCTestCase {
    private let machines = ChoiceInput(
        name: "machines",
        input: CatalogInput(type: "choice", defaultValue: nil, summary: "Machines to show.", from: "machines", many: true))!

    func testSavingAChoiceWritesOneInput() {
        let target = FakeEditTarget()
        var selection = ChoiceSelection(input: machines, current: nil, options: [
            ChoiceOption(id: "main", label: "main"), ChoiceOption(id: "here", label: "here"),
        ])
        selection.toggle("here")
        let request = WidgetChoiceRequest(entryID: "m", input: machines, title: "Machines")
        XCTAssertEqual(WidgetChoiceModel.save(selection, request: request, to: target), .saved)
        XCTAssertEqual(target.applied.first?.0, .input(name: "machines", value: .list(["main"])))
        XCTAssertEqual(target.applied.first?.1, "m")
    }

    func testAChoiceIsNotSavedWhileTheBoardCannotChange() {
        let target = FakeEditTarget()
        target.canEdit = false
        let selection = ChoiceSelection(input: machines, current: nil, options: [])
        let outcome = WidgetChoiceModel.save(
            selection, request: WidgetChoiceRequest(entryID: "m", input: machines, title: "Machines"), to: target)
        XCTAssertNotEqual(outcome, .saved)
        XCTAssertNotNil(outcome.message)
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testARefusedChoiceKeepsItsMessageAndDoesNotClose() {
        let target = FakeEditTarget()
        target.refusal = "every needs a unit"
        let selection = ChoiceSelection(input: machines, current: nil, options: [])
        let outcome = WidgetChoiceModel.save(
            selection, request: WidgetChoiceRequest(entryID: "m", input: machines, title: "Machines"), to: target)
        XCTAssertEqual(outcome, .refused("every needs a unit"))
        XCTAssertFalse(outcome.closes)
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testAValidChoiceCloses() {
        let target = FakeEditTarget()
        let selection = ChoiceSelection(input: machines, current: nil, options: [])
        let outcome = WidgetChoiceModel.save(
            selection, request: WidgetChoiceRequest(entryID: "m", input: machines, title: "Machines"), to: target)
        XCTAssertTrue(outcome.closes)
        XCTAssertNil(outcome.message)
    }
}
