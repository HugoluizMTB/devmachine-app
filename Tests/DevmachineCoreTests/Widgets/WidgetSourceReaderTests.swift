import XCTest
@testable import DevmachineCore

final class WidgetSourceReaderTests: XCTestCase {
    private let inline = WidgetScope.inline(contextKeys: [])

    private func object(_ fields: [String: WidgetValue]) -> WidgetValue { .object(fields) }

    private func problem(_ fields: [String: WidgetValue], scope: WidgetScope = .inline(contextKeys: [])) -> WidgetSpecProblem? {
        do {
            _ = try WidgetSourceReader.read(.object(fields), scope: scope)
            return nil
        } catch let problem as WidgetSpecProblem {
            return problem
        } catch {
            XCTFail("unexpected \(error)")
            return nil
        }
    }

    func testACommandTakesItsDefaults() throws {
        let source = try WidgetSourceReader.read(
            object(["kind": .string("command"), "run": .string("df"), "args": .list([.string("-h"), .string("/")]),
                    "every": .string("60s")]),
            scope: inline)
        XCTAssertEqual(source, .command(CommandSource(
            run: "df", script: nil, args: ["-h", "/"], shell: false, target: .local, every: .interval(60),
            timeout: 30, mode: .poll, keep: 200, parse: .text)))
        XCTAssertEqual(source.outputToken, "text")
    }

    func testTargetsAndNumbersInArgs() throws {
        let source = try WidgetSourceReader.read(
            object(["kind": .string("command"), "run": .string("ping"), "args": .list([.string("-c"), .int(1)]),
                    "target": .object(["workspace": .string("alice")]), "every": .string("manual")]),
            scope: inline)
        guard case let .command(command) = source else { return XCTFail("\(source)") }
        XCTAssertEqual(command.args, ["-c", "1"])
        XCTAssertEqual(command.target, .workspace("alice"))
        XCTAssertEqual(command.every, .manual)
    }

    func testAStreamHasNoEveryAndKeepsLines() throws {
        let source = try WidgetSourceReader.read(
            object(["kind": .string("command"), "run": .string("tail"),
                    "args": .list([.string("-f"), .string("/var/log/system.log")]),
                    "mode": .string("stream"), "keep": .int(500), "parse": .string("lines")]),
            scope: inline)
        guard case let .command(command) = source else { return XCTFail("\(source)") }
        XCTAssertEqual(command.every, .continuous)
        XCTAssertEqual(command.keep, 500)
    }

    func testURLPromptAndSessionDefaults() throws {
        XCTAssertEqual(
            try WidgetSourceReader.read(object(["kind": .string("url"), "url": .string("https://example.com/health"),
                                                "every": .string("30s")]), scope: inline),
            .url(URLSource(url: "https://example.com/health", every: .interval(30), timeout: 30, parse: .status)))
        XCTAssertEqual(
            try WidgetSourceReader.read(object(["kind": .string("prompt"), "harness": .string("claude"),
                                                "prompt": .string("Summarise today.")]), scope: inline),
            .prompt(PromptSource(harness: .claude, prompt: "Summarise today.", target: .local, every: .manual, timeout: 300)))
        XCTAssertEqual(
            try WidgetSourceReader.read(object(["kind": .string("session"), "session": .string("main"),
                                                "target": .object(["machine": .string("main")]),
                                                "every": .string("2s")]), scope: inline),
            .session(SessionSource(target: .machine("main"), session: "main", every: .interval(2))))
    }

    func testAProviderKeepsTheEngine10Shape() throws {
        XCTAssertEqual(
            try WidgetSourceReader.read(object(["kind": .string("provider"), "name": .string("app/clock"),
                                                "every": .string("60s")]), scope: .package),
            .provider(ProviderSource(name: "app/clock", with: [:], every: "60s")))
    }

    func testEachRuleNamesItsField() {
        let base: [String: WidgetValue] = ["kind": .string("command"), "run": .string("df"), "every": .string("60s")]
        func with(_ changes: [String: WidgetValue?]) -> [String: WidgetValue] {
            var next = base
            for (key, value) in changes { next[key] = value }
            return next
        }
        let cases: [(String, [String: WidgetValue], [String], String)] = [
            ("unknown kind", with(["kind": .string("magic")]), ["kind"], "source.kind \"magic\" is not one of"),
            ("unknown field", with(["port": .int(1)]), ["port"], "source.port is not a field of a command source"),
            ("run and script", with(["script": .string("/bin/df")]), ["script"], "takes run or script, not both"),
            ("neither", with(["run": nil]), [], "a command source needs run or script"),
            ("spaces", with(["run": .string("df -h")]), ["run"], "has spaces"),
            ("relative inline script", with(["run": nil, "script": .string("bin/df")]), ["script"],
             "a widget written in a board names an absolute path on the target"),
            ("templated script", with(["run": nil, "script": .string("/x/{{inputs.a}}")]), ["script"],
             "source.script cannot hold a template"),
            ("below minimum", with(["every": .string("1s")]), ["every"], "source.every 1s is below the command minimum of 5s"),
            ("no every", with(["every": nil]), ["every"], "needs source.every"),
            ("bad every", with(["every": .string("soon")]), ["every"], "a duration such as 60s, or manual"),
            ("timeout too long", with(["timeout": .string("11m")]), ["timeout"], "above the maximum of 10m"),
            ("zero timeout", with(["timeout": .string("0s")]), ["timeout"], "above 0"),
            ("stream with every", with(["mode": .string("stream")]), ["every"],
             "a stream runs while the widget is on screen: remove source.every"),
            ("keep without stream", with(["keep": .int(5)]), ["keep"], "source.keep is only for mode: stream"),
            ("bad parse", with(["parse": .string("yaml")]), ["parse"], "source.parse \"yaml\" is one of"),
            ("bad target", with(["target": .string("there")]), ["target"],
             "source.target is local, {machine: <name>} or {workspace: <name>}"),
            ("inputs inline", with(["args": .list([.string("{{inputs.path}}")])]), ["args", "0"],
             "a widget written in a board has no inputs"),
            ("context not given", with(["args": .list([.string("{{context.repo}}")])]), ["args", "0"],
             "needs context.repo"),
        ]
        for (name, fields, path, message) in cases {
            let found = problem(fields)
            XCTAssertEqual(found?.path, path, name)
            XCTAssertTrue(found?.message.contains(message) ?? false, "\(name): \(String(describing: found))")
        }
    }

    func testStreamRulesForTimeoutAndParse() {
        let stream: [String: WidgetValue] = ["kind": .string("command"), "run": .string("tail"), "mode": .string("stream")]
        var timed = stream
        timed["timeout"] = .string("10s")
        XCTAssertEqual(problem(timed)?.path, ["timeout"])
        var parsed = stream
        parsed["parse"] = .string("number")
        XCTAssertEqual(problem(parsed)?.message, "a stream reads text, lines or ansi, not number")
    }

    func testAPackageScriptIsRelativeAndInsideThePackage() {
        let script: [String: WidgetValue] = ["kind": .string("command"), "script": .string("widgets/disk/check.sh"),
                                             "every": .string("60s")]
        XCTAssertNil(problem(script, scope: .package))
        var absolute = script
        absolute["script"] = .string("/etc/x.sh")
        XCTAssertEqual(problem(absolute, scope: .package)?.path, ["script"])
        var escaping = script
        escaping["script"] = .string("../other/x.sh")
        XCTAssertEqual(problem(escaping, scope: .package)?.path, ["script"])
    }

    func testAPackageScriptPathIsCleanedLikeTheCLI() {
        func script(_ path: String) -> [String: WidgetValue] {
            ["kind": .string("command"), "script": .string(path), "every": .string("60s")]
        }
        XCTAssertNil(problem(script("widgets/../check.sh"), scope: .package))
        XCTAssertNil(problem(script("./check.sh"), scope: .package))
        XCTAssertEqual(problem(script("widgets/.."), scope: .package)?.path, ["script"])
        XCTAssertEqual(problem(script("widgets/../../x.sh"), scope: .package)?.path, ["script"])
    }

    func testTemplatesFollowTheCLIPattern() {
        let base: [String: WidgetValue] = ["kind": .string("command"), "run": .string("echo"), "every": .string("60s")]
        var odd = base
        odd["args"] = .list([.string("{{ what ever }}")])
        XCTAssertEqual(
            problem(odd)?.message,
            "template {{ what ever }} in source.args.0 names neither inputs.<name> nor context.<name>")
        var item = base
        item["args"] = .list([.string("{{item.name}}")])
        XCTAssertTrue(problem(item)?.message.contains("item only works inside a list view's item") ?? false)
        var nested = base
        nested["args"] = .list([.string("{{context.repo.name}}")])
        XCTAssertEqual(problem(nested, scope: .inline(contextKeys: ["repo"]))?.path, ["args", "0"])
        var given = base
        given["args"] = .list([.string("{{ context.repo }}")])
        XCTAssertNil(problem(given, scope: .inline(contextKeys: ["repo"])))
        var trailing = base
        trailing["run"] = .string("echo ")
        XCTAssertNil(problem(trailing))
    }

    func testPackageWidgetsMayUseInputs() {
        let fields: [String: WidgetValue] = [
            "kind": .string("command"), "run": .string("df"), "every": .string("60s"),
            "target": .object(["machine": .string("{{inputs.machine}}")]),
        ]
        XCTAssertNil(problem(fields, scope: .package))
    }

    func testURLAndPromptAndSessionRules() {
        XCTAssertEqual(problem(["kind": .string("url"), "url": .string("ftp://example.com"), "every": .string("30s")])?.path, ["url"])
        XCTAssertEqual(problem(["kind": .string("url"), "url": .string("https://example.com")])?.path, ["every"])
        XCTAssertEqual(problem(["kind": .string("prompt"), "harness": .string("gemini"), "prompt": .string("x")])?.path, ["harness"])
        XCTAssertEqual(problem(["kind": .string("prompt"), "harness": .string("claude"), "every": .string("1m"),
                                "prompt": .string("x")])?.message, "source.every 1m is below the prompt minimum of 15m")
        XCTAssertEqual(problem(["kind": .string("session"), "every": .string("2s")])?.path, ["session"])
    }
}
