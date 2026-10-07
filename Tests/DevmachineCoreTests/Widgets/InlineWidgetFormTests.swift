import XCTest
@testable import DevmachineCore

final class InlineWidgetFormTests: XCTestCase {
    private func filled(_ template: InlineWidgetTemplate) -> InlineWidgetForm {
        var form = InlineWidgetForm(template: template)
        form.title = "Check"
        form.run = "df"
        form.url = "https://example.com"
        form.prompt = "Summarise the log"
        form.session = "main"
        return form
    }

    func testEveryTemplateBuildsAnEntryTheBoardReaderAccepts() throws {
        for surface in ["home", "sidebar", "menubar-panel"] {
            for template in InlineWidgetTemplate.allCases {
                switch filled(template).read(surface: surface, id: "check") {
                case let .success(inline):
                    XCTAssertEqual(inline.title, "Check")
                    XCTAssertEqual(inline.source.kind, template == .urlStatus || template == .webPage ? "url" : template.rawValue)
                case let .failure(problem):
                    XCTFail("\(surface) \(template): \(problem)")
                }
            }
        }
    }

    func testTheMenuBarOffersCommandAndURLStatusOnly() {
        XCTAssertEqual(InlineWidgetTemplate.offered(on: "slot"), [.command, .urlStatus])
        XCTAssertEqual(InlineWidgetTemplate.offered(on: "canvas"), InlineWidgetTemplate.allCases)
        XCTAssertEqual(InlineWidgetForm.views(for: "number", layout: "slot"), ["number", "status"])
        XCTAssertEqual(InlineWidgetForm.views(for: "number", layout: "canvas"), ["gauge", "number", "sparkline", "status"])
        XCTAssertTrue(InlineWidgetForm.views(for: "text", layout: "canvas").contains("text"))
        XCTAssertFalse(InlineWidgetForm.views(for: "text", layout: "canvas").contains { $0.hasPrefix("app.") })
    }

    func testACommandInTheMenuBarReadsThere() {
        XCTAssertNoThrow(try filled(.command).read(surface: "menubar", id: "check").get())
        var form = filled(.command)
        form.view = "gauge"
        form.parse = "number"
        guard case let .failure(problem) = form.read(surface: "menubar", id: "check") else { return XCTFail("expected a problem") }
        XCTAssertEqual(problem.field, "view")
    }

    func testAProblemLandsOnItsField() {
        var form = filled(.command)
        form.every = "2s"
        guard case let .failure(problem) = form.read(surface: "home", id: "check") else { return XCTFail("expected a problem") }
        XCTAssertEqual(problem.field, "every")
        XCTAssertTrue(problem.message.contains("below the command minimum of 5s"), problem.message)
        XCTAssertFalse(problem.message.hasPrefix("widget"), problem.message)
        var url = filled(.urlStatus)
        url.url = ""
        guard case let .failure(urlProblem) = url.read(surface: "home", id: "check") else { return XCTFail("expected a problem") }
        XCTAssertEqual(urlProblem.field, "url")
    }

    func testAnEmptyTitleIsAskedFor() {
        var form = filled(.command)
        form.title = "  "
        XCTAssertEqual(form.read(surface: "home", id: "check"), .failure(FormProblem(field: "title", message: "Give the widget a title.")))
    }

    func testArgumentsAreOnePerLineAndAShellLineSetsShell() throws {
        var form = filled(.command)
        form.args = "-h\n\n/var/log"
        guard case let .command(command) = try form.read(surface: "home", id: "check").get().source else { return XCTFail() }
        XCTAssertEqual(command.args, ["-h", "/var/log"])
        XCTAssertFalse(command.shell)
        form.commandStyle = .shell
        form.shellLine = "df -h | tail -1"
        guard case let .command(shell) = try form.read(surface: "home", id: "check").get().source else { return XCTFail() }
        XCTAssertTrue(shell.shell)
        XCTAssertEqual(shell.run, "df -h | tail -1")
        XCTAssertEqual(shell.args, [])
    }

    func testATargetIsWrittenAsTheContractSpellsIt() throws {
        var form = filled(.session)
        form.target = .machine("main")
        XCTAssertEqual(try form.read(surface: "home", id: "check").get().source.target, .machine("main"))
        form.target = .workspace("alice-dev")
        XCTAssertEqual(try form.read(surface: "home", id: "check").get().source.target, .workspace("alice-dev"))
    }

    func testAnInlineWidgetFillsTheFormAndReadsBackTheSame() throws {
        let board = try BoardCodec.decodeStack("""
            format: 1
            surface: sidebar
            widgets:
              - id: disk
                title: Disk
                source: {kind: command, run: df, args: [-h], target: {machine: main}, every: 2m, parse: lines}
                view: {kind: text}

            """)
        let old = try XCTUnwrap(board.entries[0].inline)
        let form = try XCTUnwrap(InlineWidgetForm(inline: old, surface: "sidebar"))
        XCTAssertEqual(form.template, .command)
        XCTAssertEqual(form.args, "-h")
        XCTAssertEqual(form.target, .machine("main"))
        XCTAssertEqual(form.every, "2m")
        XCTAssertEqual(form.parse, "lines")
        let again = try form.read(surface: "sidebar", id: "disk").get()
        XCTAssertEqual(again.source, old.source)
        XCTAssertEqual(again.view, old.view)
    }

    func testAnUnchangedSourceKeepsItsTree() throws {
        let board = try BoardCodec.decodeStack("""
            format: 1
            surface: sidebar
            widgets:
              - id: disk
                title: Disk
                source: {kind: command, run: 'df', every: 60s}
                view: {kind: text}

            """)
        let old = try XCTUnwrap(board.entries[0].inline)
        var form = try XCTUnwrap(InlineWidgetForm(inline: old, surface: "sidebar"))
        form.title = "Disk use"
        let edited = try form.read(surface: "sidebar", id: "disk", keeping: old).get()
        XCTAssertEqual(edited.title, "Disk use")
        XCTAssertEqual(edited.sourceTree.emit(key: "source", indent: 4), old.sourceTree.emit(key: "source", indent: 4))
        XCTAssertEqual(edited.viewTree.emit(key: "view", indent: 4), old.viewTree.emit(key: "view", indent: 4))
        form.run = "du"
        let changed = try form.read(surface: "sidebar", id: "disk", keeping: old).get()
        XCTAssertNotEqual(changed.sourceTree.emit(key: "source", indent: 4), old.sourceTree.emit(key: "source", indent: 4))
        XCTAssertEqual(changed.viewTree.emit(key: "view", indent: 4), old.viewTree.emit(key: "view", indent: 4))
    }

    func testAWidgetTheTemplatesCannotShowHasNoForm() throws {
        let board = try BoardCodec.decodeStack("""
            format: 1
            surface: sidebar
            widgets:
              - id: log
                title: Log
                source: {kind: command, run: tail, args: [-f, /var/log/x], mode: stream}
                view: {kind: text}
              - id: clock
                title: Clock
                source: {kind: provider, name: app/clock, every: 60s}
                view: {kind: app.clock}

            """)
        XCTAssertNil(InlineWidgetForm(inline: board.entries[0].inline!, surface: "sidebar"))
        XCTAssertNil(InlineWidgetForm(inline: board.entries[1].inline!, surface: "sidebar"))
    }

    func testAQuoteOrANewLineInAValueIsWrittenSafely() throws {
        var form = filled(.prompt)
        form.prompt = "Say \"hi\"\nthen: stop"
        guard case let .prompt(prompt) = try form.read(surface: "home", id: "check").get().source else { return XCTFail() }
        XCTAssertEqual(prompt.prompt, "Say \"hi\"\nthen: stop")
    }

    func testHostileValuesArriveIntactWithNoExtraKeyOrEntry() throws {
        let hostile = [
            "x\nsource: {kind: command, run: rm}", "a]b", "a, b", "a #b", "- a", "it's", "say \"hi\"",
            "https://example.com/a#b", "a: b", "path:", "a}b", "yes", "no", "1e3", "null", "true", "~", "123",
        ]
        for text in hostile {
            var command = filled(.command)
            command.title = text
            command.run = "tool"
            command.args = text.replacingOccurrences(of: "\n", with: " ")
            command.target = .machine(text.replacingOccurrences(of: "\n", with: " "))
            let inline = try command.read(surface: "home", id: "check").get()
            XCTAssertEqual(inline.title, text)
            guard case let .command(source) = inline.source else { return XCTFail(text) }
            XCTAssertEqual(source.run, "tool")
            XCTAssertEqual(source.args, [text.replacingOccurrences(of: "\n", with: " ")].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            XCTAssertEqual(source.target, .machine(text.replacingOccurrences(of: "\n", with: " ")))

            var shell = filled(.command)
            shell.commandStyle = .shell
            shell.shellLine = text
            guard case let .command(line) = try shell.read(surface: "home", id: "check").get().source else { return XCTFail(text) }
            XCTAssertEqual(line.run, text)
            XCTAssertTrue(line.shell)

            var url = filled(.webPage)
            url.url = "https://example.com/" + text.replacingOccurrences(of: "\n", with: "")
            if case let .success(read) = url.read(surface: "home", id: "check"), case let .url(source) = read.source {
                XCTAssertEqual(source.url, url.url)
            }

            var prompt = filled(.prompt)
            prompt.prompt = text
            guard case let .prompt(asked) = try prompt.read(surface: "home", id: "check").get().source else { return XCTFail(text) }
            XCTAssertEqual(asked.prompt, text)
        }
    }

    func testURLsWithAHashAColonSpaceAndATrailingColonStayWhole() throws {
        for address in ["https://example.com/a#b", "https://example.com/a: b", "https://example.com/a:"] {
            var form = filled(.urlStatus)
            form.url = address
            guard case let .url(source) = try form.read(surface: "home", id: "check").get().source else { return XCTFail(address) }
            XCTAssertEqual(source.url, address)
        }
    }

    func testATitleOfOnlyANewLineIsAskedFor() {
        var form = filled(.command)
        form.title = "\n"
        XCTAssertEqual(form.read(surface: "home", id: "check"), .failure(FormProblem(field: "title", message: "Give the widget a title.")))
    }

    func testAnArgumentLineOfOnlySpacesIsDropped() throws {
        var form = filled(.command)
        form.args = "-h\n   \n/var/log"
        guard case let .command(command) = try form.read(surface: "home", id: "check").get().source else { return XCTFail() }
        XCTAssertEqual(command.args, ["-h", "/var/log"])
    }

    func testAZoomIsWrittenFromItsNumber() throws {
        var form = filled(.webPage)
        form.zoom = "1.5"
        XCTAssertTrue(form.yaml(surface: "home", id: "check").text.contains("zoom: 1.5\n"))
        form.zoom = "1: x"
        XCTAssertFalse(form.yaml(surface: "home", id: "check").text.contains("\n      x"))
    }
}
