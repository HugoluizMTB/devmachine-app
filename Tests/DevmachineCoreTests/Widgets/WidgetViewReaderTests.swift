import XCTest
@testable import DevmachineCore

final class WidgetViewReaderTests: XCTestCase {
    private func command(_ parse: ParseMode) -> WidgetSource {
        .command(CommandSource(run: "x", script: nil, args: [], shell: false, target: .local, every: .interval(60),
                               timeout: 30, mode: .poll, keep: 200, parse: parse))
    }

    private let url = WidgetSource.url(URLSource(url: "https://example.com", every: .interval(30), timeout: 30, parse: .status))
    private let session = WidgetSource.session(SessionSource(target: .local, session: "main", every: .interval(2)))

    private func read(
        _ fields: [String: WidgetValue], _ source: WidgetSource, writesParse: Bool = true,
        scope: WidgetScope = .inline(contextKeys: [])
    ) throws -> WidgetView {
        try WidgetViewReader.read(.object(fields), source: source, sourceWritesParse: writesParse, scope: scope)
    }

    private func problem(
        _ fields: [String: WidgetValue], _ source: WidgetSource, writesParse: Bool = true,
        scope: WidgetScope = .inline(contextKeys: [])
    ) -> WidgetSpecProblem? {
        do {
            _ = try read(fields, source, writesParse: writesParse, scope: scope)
            return nil
        } catch let problem as WidgetSpecProblem {
            return problem
        } catch {
            XCTFail("unexpected \(error)")
            return nil
        }
    }

    func testDefaults() throws {
        let view = try read(["kind": .string("text")], command(.text))
        XCTAssertEqual(view, WidgetView(kind: "text"))
        XCTAssertTrue(view.wrap)
        XCTAssertEqual(try read(["kind": .string("gauge")], command(.number)).max, 100)
        XCTAssertEqual(try read(["kind": .string("web")], url, writesParse: false).zoom, 1)
    }

    func testFieldsAreRead() throws {
        let gauge = try read(["kind": .string("gauge"), "value": .string("{{json.used}}"), "unit": .string("%"),
                              "warn": .int(80), "crit": .int(95)], command(.json))
        XCTAssertEqual(gauge.value, "{{json.used}}")
        XCTAssertEqual(gauge.warn, 80)
        XCTAssertEqual(gauge.crit, 95)
        let status = try read(["kind": .string("status"), "ok": .string("< 300"), "warn": .string("< 500")], url, writesParse: false)
        XCTAssertEqual(status.okRule, StatusRule(op: .lt, operand: .number(300)))
        XCTAssertEqual(status.warnRule, StatusRule(op: .lt, operand: .number(500)))
        let list = try read(["kind": .string("list"), "item": .object(["title": .string("{{item.name}}"),
                                                                       "link": .string("{{item.url}}")])], command(.json))
        XCTAssertEqual(list.item, ListItemTemplate(title: "{{item.name}}", subtitle: nil, status: nil, link: "{{item.url}}"))
    }

    func testTerminalTakesASessionByKind() throws {
        XCTAssertEqual(try read(["kind": .string("terminal"), "tail": .int(40)], session).tail, 40)
        XCTAssertNotNil(problem(["kind": .string("text")], session))
    }

    func testEachRuleNamesItsField() {
        let cases: [(String, [String: WidgetValue], WidgetSource, Bool, [String], String)] = [
            ("unknown kind", ["kind": .string("pie")], command(.text), true, ["kind"], "view.kind \"pie\" is not one of"),
            ("does not accept", ["kind": .string("gauge")], command(.text), true, ["kind"],
             "view.kind \"gauge\" takes number, json, and this command source gives text"),
            ("unknown field", ["kind": .string("text"), "color": .string("red")], command(.text), true, ["color"],
             "view.color is not a field of a text view"),
            ("web with parse", ["kind": .string("web")], url, true, ["kind"], "a web view loads the page itself: remove source.parse"),
            ("json needs value", ["kind": .string("number")], command(.json), true, ["value"],
             "view.value picks what to show out of the JSON"),
            ("value without json", ["kind": .string("number"), "value": .string("{{json.a}}")], command(.number), true,
             ["value"], "view.value only applies when source.parse is json"),
            ("value not a json template", ["kind": .string("number"), "value": .string("{{inputs.a}}")], command(.json),
             true, ["value"], "template {{inputs.a}} in view.value names json.<path>, like {{json.disk.used}}"),
            ("item in value", ["kind": .string("number"), "value": .string("{{item}}")], command(.json), true,
             ["value"], "template {{item}} in view.value names json.<path>, like {{json.disk.used}}"),
            ("item path needs json", ["kind": .string("list"), "item": .object(["title": .string("{{item.name}}")])],
             command(.lines), true, ["item", "title"], "template {{item.name}} in view.item.title reads a field, and only JSON items have fields: use {{item}}"),
            ("tail range", ["kind": .string("text"), "tail": .int(9000)], command(.text), true, ["tail"],
             "view.tail 9000 is outside 1 to 2000 lines"),
            ("gauge order", ["kind": .string("gauge"), "min": .int(10), "max": .int(5)], command(.number), true, ["min"],
             "view.min must be below view.max"),
            ("zoom range", ["kind": .string("web"), "zoom": .int(3)], url, false, ["zoom"], "view.zoom is between 0.5 and 2"),
            ("bad rule", ["kind": .string("status"), "ok": .string("about 300")], url, false, ["ok"],
             "view.ok \"about 300\" is not a rule"),
            ("bad format", ["kind": .string("number"), "format": .string("money")], command(.number), true, ["format"],
             "view.format \"money\" is one of plain, percent, bytes, duration"),
        ]
        for (name, fields, source, writesParse, path, message) in cases {
            let found = problem(fields, source, writesParse: writesParse)
            XCTAssertEqual(found?.path, path, name)
            XCTAssertTrue(found?.message.contains(message) ?? false, "\(name): \(String(describing: found))")
        }
    }

    func testValueMayHoldTextAroundJSONTemplatesLikeTheCLI() throws {
        for value in ["{{json.a}}%", "{{json.a}} of {{json.b}}", "{{ json.disk.used }}"] {
            XCTAssertEqual(try read(["kind": .string("number"), "value": .string(value)], command(.json)).value, value)
        }
        XCTAssertEqual(
            problem(["kind": .string("number"), "value": .string("used")], command(.json))?.message,
            "view.value \"used\" names no field: write it like \"{{json.used}}\"")
        XCTAssertEqual(problem(["kind": .string("number"), "value": .string("")], command(.json))?.path, ["value"])
        XCTAssertNil(problem(["kind": .string("number"), "value": .string("")], command(.number)))
    }

    func testItemTemplatesFollowTheCLIScopeRules() {
        func item(_ title: String, _ source: WidgetSource, scope: WidgetScope = .inline(contextKeys: ["repo"])) -> String? {
            problem(["kind": .string("list"), "item": .object(["title": .string(title)])], source, scope: scope)?.message
        }
        XCTAssertNil(item("{{item}}", command(.lines)))
        XCTAssertNil(item("{{ item }} in {{context.repo}}", command(.lines)))
        XCTAssertNil(item("{{item.name}}", command(.json)))
        XCTAssertEqual(
            item("{{item[0]}}", command(.json)),
            "template {{item[0]}} in view.item.title names neither inputs.<name> nor context.<name>")
        XCTAssertEqual(
            item("{{item.}}", command(.json)),
            "template {{item.}} in view.item.title names neither inputs.<name> nor context.<name>")
        XCTAssertEqual(
            item("{{foo}}", command(.lines)), "template {{foo}} in view.item.title names neither inputs.<name> nor context.<name>")
        XCTAssertEqual(
            item("{{inputs.label}}", command(.lines)),
            "template {{inputs.label}} in view.item.title: a widget written in a board has no inputs")
        XCTAssertNil(item("{{inputs.label}}", command(.lines), scope: .package(inputs: ["label"], contextKeys: [])))
        XCTAssertEqual(
            item("{{inputs.label}}", command(.lines), scope: .package(inputs: [], contextKeys: [])),
            "template {{inputs.label}} in view.item.title needs inputs.label")
        XCTAssertEqual(
            item("{{context.branch}}", command(.lines)),
            "template {{context.branch}} in view.item.title needs context.branch to be declared")
    }

    func testItemIsOnlyRefusedWhereTheCLIRefusesIt() {
        XCTAssertNil(problem(["kind": .string("number"), "unit": .string("{{item}}")], command(.number)))
        XCTAssertNil(problem(["kind": .string("gauge"), "unit": .string("{{item.x}}")], command(.number)))
    }

    func testTailZeroIsUnset() throws {
        XCTAssertNil(try read(["kind": .string("text"), "tail": .int(0)], command(.text)).tail)
        XCTAssertNil(try read(["kind": .string("terminal"), "tail": .int(0)], session).tail)
    }

    func testATextStatusSourceRefusesSizeRules() {
        let prompt = WidgetSource.prompt(PromptSource(harness: .claude, prompt: "x", target: .local, every: .manual, timeout: 300))
        for rule in ["< 300", "<= 300", "> 300", ">= 300"] {
            XCTAssertEqual(
                problem(["kind": .string("status"), "ok": .string(rule)], command(.text))?.message,
                "view.ok \"\(rule)\" compares by size, and this command source gives text: use == or !=")
            XCTAssertEqual(problem(["kind": .string("status"), "warn": .string(rule)], prompt)?.path, ["warn"])
            XCTAssertNil(problem(["kind": .string("status"), "ok": .string(rule)], command(.number)))
            XCTAssertNil(problem(["kind": .string("status"), "ok": .string(rule)], url, writesParse: false))
        }
        XCTAssertNil(problem(["kind": .string("status"), "ok": .string("== \"up\""), "warn": .string("!= 3")], command(.text)))
    }

    func testStatusRules() {
        XCTAssertEqual(StatusRule.parse("<= 2.5"), StatusRule(op: .le, operand: .number(2.5)))
        XCTAssertEqual(StatusRule.parse("== \"ok\""), StatusRule(op: .eq, operand: .text("ok")))
        XCTAssertEqual(StatusRule.parse("!= \"down\""), StatusRule(op: .ne, operand: .text("down")))
        XCTAssertNil(StatusRule.parse("< \"ok\""))
        XCTAssertNil(StatusRule.parse("300"))
        XCTAssertNil(StatusRule.parse("< 1e3"))
        XCTAssertNil(StatusRule.parse("> inf"))
        XCTAssertNil(StatusRule.parse("== \"a\"b\""))
        XCTAssertNil(StatusRule.parse("< ٣"))
        XCTAssertEqual(StatusRule.parse("\n< 300\n"), StatusRule(op: .lt, operand: .number(300)))
        XCTAssertEqual(StatusRule.parse("<\n300"), StatusRule(op: .lt, operand: .number(300)))
        XCTAssertEqual(StatusRule.parse("== \"\""), StatusRule(op: .eq, operand: .text("")))
        XCTAssertEqual(StatusRule.parse(">= -1"), StatusRule(op: .ge, operand: .number(-1)))
    }
}
