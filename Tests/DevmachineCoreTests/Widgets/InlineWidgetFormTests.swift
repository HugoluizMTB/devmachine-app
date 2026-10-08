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

    func testTheCheckedHomeEntryIsAutoOnlyForAViewThatGrows() {
        var form = filled(.command)
        form.view = "text"
        let grows = form.yaml(surface: "home", id: "check").text
        XCTAssertTrue(grows.contains("    frame: {x: 0, y: 0, w: 320}\n    size: auto\n"))
        form.parse = "number"
        form.view = "gauge"
        let fixed = form.yaml(surface: "home", id: "check").text
        XCTAssertTrue(fixed.contains("    frame: {x: 0, y: 0, w: 320, h: 160}\n    size: medium\n"))
    }

    func testAValueIsWrittenOnlyWhenTheViewUsesIt() {
        var form = filled(.command)
        form.parse = "json"
        form.view = "number"
        form.value = "{{json.used}}"
        XCTAssertTrue(form.fields.contains("value"))
        XCTAssertTrue(form.yaml(surface: "home", id: "check").text.contains("value: "))
        form.view = "list"
        XCTAssertFalse(form.fields.contains("value"))
        XCTAssertFalse(form.yaml(surface: "home", id: "check").text.contains("value: "))
        form.view = "number"
        form.parse = "number"
        XCTAssertFalse(form.fields.contains("value"))
        XCTAssertFalse(form.yaml(surface: "home", id: "check").text.contains("value: "))
    }

    func testEachTemplateShowsItsOwnFields() {
        XCTAssertEqual(filled(.urlStatus).fields, ["title", "url", "every"])
        XCTAssertEqual(filled(.webPage).fields, ["title", "url", "every", "zoom"])
        XCTAssertEqual(filled(.session).fields, ["title", "target", "session", "every"])
        XCTAssertEqual(filled(.prompt).fields, ["title", "harness", "permissionMode", "prompt", "target", "every"])
        XCTAssertEqual(filled(.command).fields, ["title", "run", "args", "target", "every", "parse", "view"])
        var shell = filled(.command)
        shell.commandStyle = .shell
        XCTAssertEqual(shell.fields, ["title", "shellLine", "target", "every", "parse", "view"])
    }

    func testTemplatesNameThemselvesInAHeading() {
        XCTAssertEqual(InlineWidgetTemplate.allCases.map(\.noun), ["command", "URL status", "web page", "prompt", "session"])
    }

    func testThePickerListsOnlyTheChosenHarnesssModesFromTheContract() {
        let byHarness = WidgetContract.current.sources["prompt"]?.fields["permission_mode"]?.byHarness ?? [:]
        var form = filled(.prompt)
        XCTAssertEqual(form.permissionMode, "")
        XCTAssertEqual(form.permissionModes(), byHarness["claude"])
        form.choosePermissionMode("acceptEdits")
        form.chooseHarness("codex")
        XCTAssertEqual(form.permissionModes(), byHarness["codex"])
        XCTAssertEqual(form.permissionMode, "")
        form.choosePermissionMode("workspace-write")
        form.chooseHarness("codex")
        XCTAssertEqual(form.permissionMode, "workspace-write")
    }

    func testAModeWithNoChecksSetsEveryToManualAndLocksIt() {
        var form = filled(.prompt)
        form.every = "30m"
        form.choosePermissionMode("auto")
        XCTAssertEqual(form.every, "30m")
        XCTAssertFalse(form.everyLocked())
        form.choosePermissionMode("bypassPermissions")
        XCTAssertEqual(form.every, "manual")
        XCTAssertTrue(form.everyLocked())
        form.choosePermissionMode("plan")
        XCTAssertFalse(form.everyLocked())
        XCTAssertEqual(form.every, "manual")
        XCTAssertFalse(filled(.command).everyLocked())
    }

    func testAPermissionModeIsWrittenReadAndFilledBack() throws {
        let plain = filled(.prompt)
        XCTAssertFalse(plain.yaml(surface: "home", id: "check").text.contains("permission_mode"))
        var form = filled(.prompt)
        form.chooseHarness("codex")
        form.choosePermissionMode("danger-full-access")
        let text = form.yaml(surface: "home", id: "check").text
        XCTAssertTrue(text.contains("      harness: codex\n      permission_mode: danger-full-access\n      prompt: "))
        let inline = try form.read(surface: "home", id: "check").get()
        guard case let .prompt(source) = inline.source else { return XCTFail() }
        XCTAssertEqual(source.permissionMode, "danger-full-access")
        XCTAssertEqual(source.every, .manual)
        let again = try XCTUnwrap(InlineWidgetForm(inline: inline, surface: "home"))
        XCTAssertEqual(again.permissionMode, "danger-full-access")
        XCTAssertTrue(again.everyLocked())
        var renamed = again
        renamed.title = "Other"
        let kept = try renamed.read(surface: "home", id: "check", keeping: inline).get()
        XCTAssertEqual(kept.sourceTree, inline.sourceTree)
    }

    func testATimerOnAModeWithNoChecksLandsOnTheModeField() {
        var form = filled(.prompt)
        form.choosePermissionMode("bypassPermissions")
        form.every = "30m"
        guard case let .failure(problem) = form.read(surface: "home", id: "check") else { return XCTFail("read") }
        XCTAssertEqual(problem.field, "permissionMode")
        XCTAssertTrue(problem.message.contains("runs without any check, so it runs only when you press refresh"), problem.message)
    }

    private func minimum(of kind: String) throws -> String {
        try XCTUnwrap(WidgetContract.current.sources[kind]?.minEvery)
    }

    func testTheEveryLabelNamesTheSourceKindsOwnMinimum() throws {
        XCTAssertEqual(filled(.command).everyLabel(), "Every (at least \(try minimum(of: "command")), or manual)")
        XCTAssertEqual(filled(.prompt).everyLabel(), "Every (at least \(try minimum(of: "prompt")), or manual)")
        XCTAssertEqual(filled(.urlStatus).everyLabel(), "Every (at least \(try minimum(of: "url")), or manual)")
        XCTAssertEqual(filled(.session).everyLabel(), "Every (at least \(try minimum(of: "session")), or manual)")
    }

    func testAPromptBelowItsMinimumKeepsTheLowercaseSourceEveryName() throws {
        var form = filled(.prompt)
        form.every = "1s"
        guard case let .failure(problem) = form.read(surface: "home", id: "check") else { return XCTFail("expected a refusal") }
        XCTAssertTrue(problem.message.hasPrefix("source.every 1s"), problem.message)
        XCTAssertTrue(problem.message.contains(try minimum(of: "prompt")), problem.message)
    }

    func testPlainCapitalisesAWordButNeverAFieldPath() {
        XCTAssertEqual(InlineWidgetForm.plain("w: every manual is not allowed", id: "w"), "Every manual is not allowed")
        XCTAssertEqual(InlineWidgetForm.plain("source.every 1s is low", id: "w"), "source.every 1s is low")
        XCTAssertEqual(InlineWidgetForm.plain("w: source.every 1s is low", id: "w"), "source.every 1s is low")
    }
}
