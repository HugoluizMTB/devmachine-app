import XCTest
@testable import DevmachineCore

final class TypedEntryFormTests: XCTestCase {
    private let machines = CatalogWidget(
        name: "acme/status", fits: ["canvas", "stack"],
        inputs: [
            "machines": CatalogInput(type: "choice", defaultValue: nil, summary: "Machines.", from: "machines", many: true),
            "limit": CatalogInput(type: "number", defaultValue: .int(5), summary: "How many."),
            "label": CatalogInput(type: "string", defaultValue: nil, summary: "Label."),
            "compact": CatalogInput(type: "boolean", defaultValue: .bool(false), summary: "Compact."),
        ],
        source: CatalogSource(name: "app/machines", with: ["machines": "{{inputs.machines}}"], every: "90s"),
        viewKind: "app.machines", sizes: ["medium"], defaultSize: "medium")
    private let tail = CatalogWidget(
        name: "acme/tail", fits: ["canvas", "stack"],
        source: CatalogSource(raw: .object([
            "kind": .string("command"), "run": .string("tail"), "args": .list([.string("-f"), .string("/var/log/x")]),
            "mode": .string("stream"),
        ])),
        viewKind: "text", sizes: ["medium"], defaultSize: "medium", origin: "local")

    private var catalog: WidgetCatalog { WidgetCatalog(engine: "1.5", packagesRelease: "r", widgets: [machines, tail]) }

    private func form(_ type: String = "acme/status", with: [String: BoardScalar] = ["other": .string("kept")]) -> TypedEntryForm {
        let widget = BoardWidget(id: "w", type: type, with: with, frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0)
        return TypedEntryForm(entry: EditableEntry(widget), widget: catalog.widget(named: type)!)
    }

    func testATitleAndEveryBecomeOverrides() throws {
        var form = form()
        form.title = "Servers"
        form.every = "2m"
        form.choices["machines"] = .list(["main"])
        form.texts["limit"] = "10"
        form.texts["label"] = "prod"
        form.flags["compact"] = true
        XCTAssertEqual(
            try form.edit(surface: "home", catalog: catalog).get(),
            .typed(title: "Servers", with: [
                "machines": .list(["main"]), "limit": .int(10), "label": .string("prod"), "compact": .bool(true),
                "other": .string("kept"),
            ], every: "2m"))
    }

    func testEmptyFieldsClearTheOverridesAndDefaultsWriteNothing() throws {
        var form = form(with: ["label": .string("prod")])
        form.texts["label"] = ""
        form.texts["limit"] = "5"
        XCTAssertEqual(try form.edit(surface: "sidebar", catalog: catalog).get(), .typed(title: nil, with: [:], every: nil))
    }

    func testEveryBelowTheFloorLandsOnTheEveryField() {
        var form = form()
        form.every = "1s"
        XCTAssertEqual(
            form.edit(surface: "home", catalog: catalog),
            .failure(FormProblem(field: "every", message: "Every 1s is below acme/status's minimum of 5s")))
    }

    func testAnEveryThatIsNotADurationLandsOnTheEveryField() {
        var form = form()
        form.every = "soon"
        guard case let .failure(problem) = form.edit(surface: "home", catalog: catalog) else { return XCTFail("expected a problem") }
        XCTAssertEqual(problem.field, "every")
    }

    func testAStreamTakesNoEvery() {
        var form = form("acme/tail", with: [:])
        form.every = "60s"
        guard case let .failure(problem) = form.edit(surface: "home", catalog: catalog) else { return XCTFail("expected a problem") }
        XCTAssertEqual(problem.field, "every")
    }

    func testANumberInputMustBeANumber() {
        var form = form()
        form.texts["limit"] = "many"
        XCTAssertEqual(
            form.edit(surface: "home", catalog: catalog),
            .failure(FormProblem(field: "input.limit", message: "Limit is a number, such as 5.")))
    }

    func testTheFormStartsFromTheEntry() {
        let widget = BoardWidget(
            id: "w", type: "acme/status", with: ["limit": .int(3), "machines": .list(["here"])],
            frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0, titleOverride: "Mine", everyOverride: "5m")
        let form = TypedEntryForm(entry: EditableEntry(widget), widget: machines)
        XCTAssertEqual(form.title, "Mine")
        XCTAssertEqual(form.every, "5m")
        XCTAssertEqual(form.texts["limit"], "3")
        XCTAssertEqual(form.choices["machines"], .list(["here"]))
        XCTAssertEqual(form.plainInputs.map(\.name), ["compact", "label", "limit"])
        XCTAssertEqual(form.choiceInputs.map(\.name), ["machines"])
        XCTAssertEqual(form.everyPlaceholder, "90s")
    }

    private func titled(_ type: String = "acme/status") -> TypedEntryForm {
        let widget = BoardWidget(
            id: "w", type: type, with: [:], frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0,
            titleOverride: "Mine")
        return TypedEntryForm(entry: EditableEntry(widget), widget: catalog.widget(named: type)!)
    }

    func testAnEmptyOrBlankTitleClearsTheOverride() throws {
        for blank in ["", "   ", " \n "] {
            var form = titled()
            form.title = blank
            XCTAssertEqual(try form.edit(surface: "home", catalog: catalog).get(), .typed(title: nil, with: [:], every: nil), blank)
        }
    }

    func testABelowFloorEveryDoesNotSaveWhenTheWidgetIsNotReady() {
        let missing = CatalogWidget(
            name: "acme/gone", fits: ["canvas", "stack"],
            source: CatalogSource(name: "app/machines", with: [:], every: "90s"),
            viewKind: "app.machines", sizes: ["medium"], defaultSize: "medium",
            available: false, unavailableReason: "Add the acme package.")
        let cat = WidgetCatalog(engine: "1.5", packagesRelease: "r", widgets: [missing])
        let widget = BoardWidget(id: "w", type: "acme/gone", with: [:], frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0)
        var form = TypedEntryForm(entry: EditableEntry(widget), widget: missing)
        form.every = "1s"
        guard case let .failure(problem) = form.edit(surface: "home", catalog: cat) else { return XCTFail("expected a problem") }
        XCTAssertEqual(problem.field, "every")
    }

    func testManualIsRefusedOnAProviderWidget() {
        var form = form()
        form.every = "manual"
        guard case let .failure(problem) = form.edit(surface: "home", catalog: catalog) else { return XCTFail("expected a problem") }
        XCTAssertEqual(problem.field, "every")
    }

    func testAnEmptyListAndUndeclaredChoicesWriteNothing() throws {
        var form = form(with: [:])
        form.choices["machines"] = .list([])
        form.choices["ghost"] = .string("x")
        XCTAssertEqual(try form.edit(surface: "home", catalog: catalog).get(), .typed(title: nil, with: [:], every: nil))
    }

    func testAChoiceEditReplacesTheList() throws {
        var form = form(with: ["machines": .list(["a"])])
        form.choices["machines"] = .list(["b", "c"])
        XCTAssertEqual(
            try form.edit(surface: "home", catalog: catalog).get(), .typed(title: nil, with: ["machines": .list(["b", "c"])], every: nil))
    }

    func testABooleanBackToItsDefaultWritesNothing() throws {
        var form = form(with: ["compact": .bool(true)])
        XCTAssertEqual(form.flags["compact"], true)
        form.flags["compact"] = false
        XCTAssertEqual(try form.edit(surface: "home", catalog: catalog).get(), .typed(title: nil, with: [:], every: nil))
    }

    func testNanAndInfinityAreNotNumbers() {
        for text in ["nan", "inf", "-inf", "Infinity"] {
            var form = form()
            form.texts["limit"] = text
            guard case let .failure(problem) = form.edit(surface: "home", catalog: catalog) else { return XCTFail("\(text) accepted") }
            XCTAssertEqual(problem.field, "input.limit")
        }
    }

    func testANumberEqualToTheDefaultWritesNothing() throws {
        var form = form(with: [:])
        form.texts["limit"] = "5.0"
        XCTAssertEqual(try form.edit(surface: "home", catalog: catalog).get(), .typed(title: nil, with: [:], every: nil))
    }

    func testAnInputNamedLikeAnEntryKeyMapsToItsInputField() {
        let text = "widgets:\n  - id: w\n    title: T\n    with:\n      title: x\n      every: y\n    every: 5m\n"
        XCTAssertEqual(TypedEntryForm.field(atLine: 5, in: text), "input.title")
        XCTAssertEqual(TypedEntryForm.field(atLine: 6, in: text), "input.every")
        XCTAssertEqual(TypedEntryForm.field(atLine: 3, in: text), "title")
        XCTAssertEqual(TypedEntryForm.field(atLine: 7, in: text), "every")
        XCTAssertNil(TypedEntryForm.field(atLine: 2, in: text))
    }
}
