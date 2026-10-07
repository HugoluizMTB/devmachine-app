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
    var hasRoom = true

    func editableEntry(_ id: String) -> EditableEntry? { entries[id] }

    var refusal: String?

    func problem(with edit: EntryEdit, for id: String) -> String? { refusal }

    func apply(_ edit: EntryEdit, to id: String) -> Bool {
        if refusal != nil { return false }
        applied.append((edit, id))
        return true
    }

    func addInline(_ inline: InlineWidget, title: String, preset: String) -> String? {
        guard hasRoom else { return nil }
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

    func testAStreamTheTemplatesCannotShowOffersItsTitleAndNoEvery() throws {
        let target = FakeEditTarget()
        target.editSurface = "sidebar"
        let old = try inline("  - id: log\n    title: Log\n    source: {kind: command, run: tail, args: [-f, x], mode: stream}\n    view: {kind: text}\n")
        target.entries["log"] = EditableEntry(StackEntry(id: "log", type: "", inline: old))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("log"), target: target))
        guard case var .basics(form) = model.form else { return XCTFail() }
        XCTAssertEqual(form.title, "Log")
        XCTAssertNil(form.every)
        XCTAssertEqual(model.shownFields, ["title"])
        form.title = "Live log"
        model.form = .basics(form)
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

    func testATypedEntryMissingFromTheCatalogEditsItsTitleOnly() throws {
        let target = FakeEditTarget()
        target.entries["s"] = EditableEntry(BoardWidget(
            id: "s", type: "acme/gone", with: ["label": .string("prod")], frame: BoardFrame(x: 0, y: 0, w: 1, h: 1),
            size: "medium", z: 0, everyOverride: "90s"))
        XCTAssertTrue(target.offersEdit("s"))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("s"), target: target))
        guard case let .titleOnly(entry, title) = model.form else { return XCTFail() }
        XCTAssertEqual(title, "")
        XCTAssertEqual(model.shownFields, ["title"])
        model.form = .titleOnly(entry, title: "Servers")
        XCTAssertTrue(model.save(to: target))
        XCTAssertEqual(target.applied.first?.0, .typed(title: "Servers", with: ["label": .string("prod")], every: "90s"))
    }

    func testNoEditForAnEntryNoLongerOnTheBoard() {
        let target = FakeEditTarget()
        XCTAssertNil(WidgetEditorModel(request: .edit("gone"), target: target))
        XCTAssertFalse(target.offersEdit("gone"))
    }

    private let clockYAML = "  - id: clock\n    title: Clock\n    source: {kind: provider, name: app/clock, every: 60s}\n    view: {kind: app.clock}\n"

    func testAnInlineWidgetTheTemplatesCannotShowChangesItsEvery() throws {
        let target = FakeEditTarget()
        target.editSurface = "sidebar"
        let old = try inline(clockYAML)
        target.entries["clock"] = EditableEntry(StackEntry(id: "clock", type: "", inline: old))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("clock"), target: target))
        guard case var .basics(form) = model.form else { return XCTFail() }
        XCTAssertEqual(form.every, "60s")
        XCTAssertEqual(model.shownFields, ["title", "every"])
        form.every = "30s"
        model.form = .basics(form)
        XCTAssertTrue(model.save(to: target))
        guard case let .inline(saved)? = target.applied.first?.0 else { return XCTFail() }
        XCTAssertEqual(saved.source.every, .interval(30))
        XCTAssertEqual(saved.sourceTree.emit(key: "source", indent: 4), ["    source: {kind: provider, name: app/clock, every: 30s}"])
        XCTAssertEqual(saved.viewTree, old.viewTree)
    }

    func testAnEveryBelowTheMinimumStaysUnderItsField() throws {
        let target = FakeEditTarget()
        target.editSurface = "sidebar"
        let old = try inline(clockYAML)
        target.entries["clock"] = EditableEntry(StackEntry(id: "clock", type: "", inline: old))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("clock"), target: target))
        guard case var .basics(form) = model.form else { return XCTFail() }
        form.every = "1s"
        model.form = .basics(form)
        XCTAssertFalse(model.save(to: target))
        XCTAssertNotNil(model.problem(for: "every"))
        XCTAssertTrue(target.applied.isEmpty)
    }

    func testAnUnchangedEveryKeepsTheSourceAsWritten() throws {
        let target = FakeEditTarget()
        target.editSurface = "sidebar"
        let old = try inline(clockYAML)
        target.entries["clock"] = EditableEntry(StackEntry(id: "clock", type: "", inline: old))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("clock"), target: target))
        guard case var .basics(form) = model.form else { return XCTFail() }
        form.title = "Time"
        model.form = .basics(form)
        XCTAssertTrue(model.save(to: target))
        guard case let .inline(saved)? = target.applied.first?.0 else { return XCTFail() }
        XCTAssertEqual(saved.sourceTree, old.sourceTree)
        XCTAssertEqual(saved.title, "Time")
    }

    func testValueIsWrittenOnlyWhenTheViewUsesIt() throws {
        let target = FakeEditTarget()
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.command), target: target))
        guard case var .inline(form, nil) = model.form else { return XCTFail() }
        form.title = "Disk"
        form.run = "df"
        form.parse = "json"
        form.view = "number"
        form.value = "{{json.used}}"
        model.form = .inline(form, old: nil)
        XCTAssertTrue(model.shownFields.contains("value"))
        form.parse = "text"
        form.view = "text"
        model.form = .inline(form, old: nil)
        XCTAssertFalse(model.shownFields.contains("value"))
        XCTAssertTrue(model.save(to: target))
        XCTAssertNil(target.added.first?.0.view.value)
    }

    func testAProblemOnAFieldTheFormHidesShowsInTheBanner() throws {
        let target = FakeEditTarget()
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.urlStatus), target: target))
        guard case var .inline(form, nil) = model.form else { return XCTFail() }
        form.title = "Site"
        form.url = "https://example.com"
        form.view = "markdown"
        model.form = .inline(form, old: nil)
        XCTAssertFalse(model.save(to: target))
        XCTAssertFalse(model.shownFields.contains("view"))
        XCTAssertNil(model.problem(for: "view"))
        XCTAssertNotNil(model.formProblem)
    }

    func testTheHeadingUsesTheTemplatesOwnWords() throws {
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.urlStatus), target: FakeEditTarget()))
        XCTAssertEqual(model.heading, "New URL status widget")
    }

    func testEditingAShowableInlineWidgetAppliesItAndKeepsTheView() throws {
        let target = FakeEditTarget()
        target.editSurface = "sidebar"
        let old = try inline("  - id: site\n    title: Site\n    source: {kind: url, url: \"https://example.com\", every: 60s, parse: status}\n    view: {kind: status}\n")
        target.entries["site"] = EditableEntry(StackEntry(id: "site", type: "", inline: old))
        let model = try XCTUnwrap(WidgetEditorModel(request: .edit("site"), target: target))
        guard case .inline(var form, old?) = model.form else { return XCTFail() }
        form.url = "https://example.com/health"
        model.form = .inline(form, old: old)
        XCTAssertTrue(model.save(to: target))
        XCTAssertEqual(target.applied.first?.1, "site")
        guard case let .inline(saved)? = target.applied.first?.0 else { return XCTFail() }
        XCTAssertEqual(saved.viewTree, old.viewTree)
        guard case let .url(url) = saved.source else { return XCTFail() }
        XCTAssertEqual(url.url, "https://example.com/health")
    }

    func testNoRoomForAnotherWidgetStaysOnTheForm() throws {
        let target = FakeEditTarget()
        target.hasRoom = false
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.urlStatus), target: target))
        guard case var .inline(form, nil) = model.form else { return XCTFail() }
        form.title = "Site"
        form.url = "https://example.com"
        model.form = .inline(form, old: nil)
        XCTAssertFalse(model.save(to: target))
        XCTAssertEqual(model.formProblem, "There is no room for another widget here.")
    }

    func testANewWidgetOpensOnlyOnceTheGalleryIsGone() {
        var handoff = NewWidgetHandoff()
        XCTAssertNil(handoff.galleryGone())
        handoff.choose(.webPage)
        XCTAssertEqual(handoff.galleryGone(), .new(.webPage))
        XCTAssertNil(handoff.galleryGone())
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

    func testANewPromptSavesItsModeAndAModeWithNoChecksStaysManual() throws {
        let target = FakeEditTarget()
        let model = try XCTUnwrap(WidgetEditorModel(request: .new(.prompt), target: target))
        guard case var .inline(form, nil) = model.form else { return XCTFail() }
        XCTAssertTrue(model.shownFields.contains("permissionMode"))
        form.title = "Go news"
        form.prompt = "Search the web for this week's Go release notes."
        form.chooseHarness("codex")
        XCTAssertEqual(form.permissionModes(), WidgetContract.current.sources["prompt"]?.fields["permission_mode"]?.byHarness?["codex"])
        form.choosePermissionMode("dangerously-bypass-approvals-and-sandbox")
        XCTAssertTrue(form.everyLocked())
        model.form = .inline(form, old: nil)
        XCTAssertTrue(model.save(to: target))
        guard case let .prompt(source)? = target.added.first?.0.source else { return XCTFail("\(target.added)") }
        XCTAssertEqual(source.harness, .codex)
        XCTAssertEqual(source.permissionMode, "dangerously-bypass-approvals-and-sandbox")
        XCTAssertEqual(source.every, .manual)
    }
}
