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

    private let disk = CatalogWidget(
        name: "acme/status", fits: ["canvas", "stack"],
        inputs: ["label": CatalogInput(type: "string", defaultValue: nil, summary: "Label.")],
        source: CatalogSource(name: "app/machines", every: "90s"), viewKind: "app.machines", sizes: ["medium"],
        defaultSize: "medium")

    private func inline(_ yaml: String) throws -> InlineWidget {
        try XCTUnwrap(BoardCodec.decodeStack("format: 1\nsurface: sidebar\nwidgets:\n" + yaml).entries[0].inline)
    }

    func testANewCommandIsAddedThroughTheTarget() throws {
        let target = FakeEditTarget()
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.command), target: target))
        XCTAssertEqual(model.heading, "New command widget")
        guard case var .inline(form, nil) = model.form else { return XCTFail() }
        form.title = "Disk"
        form.run = "df"
        model.form = .inline(form, old: nil)
        XCTAssertTrue(model.save(to: target))
        XCTAssertEqual(target.added.first?.1, "Disk")
        XCTAssertEqual(target.added.first?.2, "medium")
        XCTAssertEqual(target.added.first?.0.source.kind, "command")
    }

    func testAProblemStaysOnTheFormAndNothingIsWritten() throws {
        let target = FakeEditTarget()
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.command), target: target))
        guard case var .inline(form, nil) = model.form else { return XCTFail() }
        form.title = "Disk"
        form.run = "df"
        form.every = "2s"
        model.form = .inline(form, old: nil)
        XCTAssertFalse(model.save(to: target))
        XCTAssertNotNil(model.problem(for: "every"))
        XCTAssertTrue(target.added.isEmpty)
    }

    func testAnInlineWidgetTheTemplatesCannotShowOffersTheTitleOnly() throws {
        let target = FakeEditTarget()
        target.editSurface = "sidebar"
        let old = try inline("  - id: log\n    title: Log\n    source: {kind: command, run: tail, args: [-f, x], mode: stream}\n    view: {kind: text}\n")
        target.entries["log"] = EditableEntry(StackEntry(id: "log", type: "", inline: old))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("log"), target: target))
        XCTAssertEqual(model.form, .titleOnly("Log", old: old))
        model.form = .titleOnly("Live log", old: old)
        XCTAssertTrue(model.save(to: target))
        guard case let .inline(saved)? = target.applied.first?.0 else { return XCTFail() }
        XCTAssertEqual(saved.title, "Live log")
        XCTAssertEqual(saved.sourceTree.emit(key: "source", indent: 4), old.sourceTree.emit(key: "source", indent: 4))
    }

    func testEditingAPackageWidgetWritesATypedEdit() throws {
        let target = FakeEditTarget()
        target.editCatalog = WidgetCatalog(engine: "1.5", packagesRelease: "r", widgets: [disk])
        target.entries["s"] = EditableEntry(BoardWidget(
            id: "s", type: "acme/status", frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("s"), target: target))
        guard case var .typed(form) = model.form else { return XCTFail() }
        form.title = "Servers"
        form.texts["label"] = "prod"
        model.form = .typed(form)
        XCTAssertTrue(model.save(to: target))
        XCTAssertEqual(target.applied.first?.0, .typed(title: "Servers", with: ["label": .string("prod")], every: nil))
    }

    func testNoEditForATypedEntryMissingFromTheCatalog() {
        let target = FakeEditTarget()
        target.entries["s"] = EditableEntry(BoardWidget(
            id: "s", type: "acme/gone", frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0))
        XCTAssertNil(WidgetEditorModel(request: .edit("s"), target: target))
        XCTAssertFalse(target.offersEdit("s"))
    }

    func testNothingIsSavedWhileTheBoardCannotChange() throws {
        let target = FakeEditTarget()
        target.canEdit = false
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.urlStatus), target: target))
        XCTAssertFalse(model.save(to: target))
        XCTAssertEqual(model.problem?.message, "home.yml cannot change right now: fix the file first.")
    }

    func testAnEditTheBoardRefusesShowsItsReasonOnTheForm() throws {
        let target = FakeEditTarget()
        target.editCatalog = WidgetCatalog(engine: "1.5", packagesRelease: "r", widgets: [disk])
        target.entries["s"] = EditableEntry(BoardWidget(
            id: "s", type: "acme/status", frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0))
        target.refusal = "s: acme/status has no input \"label\""
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("s"), target: target))
        guard case var .typed(form) = model.form else { return XCTFail() }
        form.texts["label"] = "prod"
        model.form = .typed(form)
        XCTAssertFalse(model.save(to: target))
        XCTAssertEqual(model.formProblem, "s: acme/status has no input \"label\"")
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testAnEditOfAWidgetNoLongerOnTheBoardIsRefused() throws {
        let target = FakeEditTarget()
        let old = try inline("  - id: log\n    title: Log\n    source: {kind: command, run: tail, args: [-f, x], mode: stream}\n    view: {kind: text}\n")
        target.entries["log"] = EditableEntry(StackEntry(id: "log", type: "", inline: old))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("log"), target: target))
        target.entries["log"] = nil
        XCTAssertFalse(model.save(to: target))
        XCTAssertEqual(model.formProblem, "This widget is no longer on the board.")
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testEditRequestsHaveStableIDs() {
        XCTAssertEqual(WidgetEditRequest.new(.urlStatus).id, "new/url-status")
        XCTAssertEqual(WidgetEditRequest.edit("disk").id, "edit/disk")
    }

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
