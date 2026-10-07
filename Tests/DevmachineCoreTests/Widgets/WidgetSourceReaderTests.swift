import XCTest
@testable import DevmachineCore

final class WidgetSourceReaderTests: XCTestCase {
    private let inline = WidgetScope.inline(contextKeys: [])
    private let packageScope = WidgetScope.package(inputs: [], contextKeys: [])

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
                                                "every": .string("60s")]), scope: packageScope),
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
            ("run and script", with(["script": .string("/bin/df")]), ["script"], "has run or script, not both"),
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
             "source.target \"there\": write local, {machine: <name>} or {workspace: <name>}"),
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
        XCTAssertNil(problem(script, scope: packageScope))
        var absolute = script
        absolute["script"] = .string("/etc/x.sh")
        XCTAssertEqual(problem(absolute, scope: packageScope)?.path, ["script"])
        var escaping = script
        escaping["script"] = .string("../other/x.sh")
        XCTAssertEqual(problem(escaping, scope: packageScope)?.path, ["script"])
    }

    func testAPackageScriptPathIsCleanedLikeTheCLI() {
        func script(_ path: String) -> [String: WidgetValue] {
            ["kind": .string("command"), "script": .string(path), "every": .string("60s")]
        }
        XCTAssertNil(problem(script("widgets/../check.sh"), scope: packageScope))
        XCTAssertNil(problem(script("./check.sh"), scope: packageScope))
        XCTAssertEqual(problem(script("widgets/.."), scope: packageScope)?.path, ["script"])
        XCTAssertEqual(problem(script("widgets/../../x.sh"), scope: packageScope)?.path, ["script"])
    }

    func testTemplatesFollowTheCLIPattern() {
        let base: [String: WidgetValue] = ["kind": .string("command"), "run": .string("echo"), "every": .string("60s")]
        var odd = base
        odd["args"] = .list([.string("{{ what ever }}")])
        XCTAssertEqual(
            problem(odd)?.message,
            "template {{ what ever }} in source.args[0] names neither inputs.<name> nor context.<name>")
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

    func testRunRefusesAnyWhitespaceWithoutShell() {
        for run in ["df\r-h", "df\u{00A0}-h", "df\u{2003}-h", "df\u{3000}-h", "df\u{0B}-h"] {
            let fields: [String: WidgetValue] = ["kind": .string("command"), "run": .string(run), "every": .string("60s")]
            XCTAssertEqual(problem(fields, scope: .inline(contextKeys: ["repo"]))?.path, ["run"], run.debugDescription)
            var shell = fields
            shell["shell"] = .bool(true)
            XCTAssertNil(problem(shell, scope: .inline(contextKeys: ["repo"])), run.debugDescription)
        }
    }

    func testPackageTemplatesNameDeclaredInputsAndContext() {
        let fields: [String: WidgetValue] = [
            "kind": .string("command"), "run": .string("df"), "every": .string("60s"),
            "args": .list([.string("{{inputs.path}}"), .string("{{context.repo}}")]),
        ]
        XCTAssertNil(problem(fields, scope: .package(inputs: ["path"], contextKeys: ["repo"])))
        XCTAssertEqual(
            problem(fields, scope: .package(inputs: [], contextKeys: ["repo"]))?.message,
            "template {{inputs.path}} in source.args[0] needs inputs.path")
        XCTAssertEqual(
            problem(fields, scope: .package(inputs: ["path"], contextKeys: []))?.message,
            "template {{context.repo}} in source.args[1] needs context.repo to be declared")
    }

    func testAnEmptyRunOrScriptIsUnset() throws {
        XCTAssertEqual(
            problem(["kind": .string("command"), "run": .string(""), "every": .string("60s")])?.message,
            "a command source needs run or script")
        let source = try WidgetSourceReader.read(
            object(["kind": .string("command"), "run": .string(""), "script": .string("/usr/local/bin/check"),
                    "every": .string("60s")]),
            scope: inline)
        guard case let .command(command) = source else { return XCTFail("\(source)") }
        XCTAssertNil(command.run)
        XCTAssertEqual(command.script, "/usr/local/bin/check")
        XCTAssertNil(problem(["kind": .string("command"), "run": .string("df"), "script": .null, "every": .string("60s")]))
    }

    func testABlankPromptOrSessionCountsNewlines() {
        XCTAssertEqual(
            problem(["kind": .string("prompt"), "harness": .string("claude"), "prompt": .string("\n\t\n")])?.path, ["prompt"])
        XCTAssertEqual(problem(["kind": .string("session"), "session": .string("\n"), "every": .string("2s")])?.path, ["session"])
    }

    func testKeepZeroIsUnset() throws {
        XCTAssertNil(problem(["kind": .string("command"), "run": .string("df"), "every": .string("60s"), "keep": .int(0)]))
        let source = try WidgetSourceReader.read(
            object(["kind": .string("command"), "run": .string("tail"), "mode": .string("stream"), "keep": .int(0)]),
            scope: inline)
        guard case let .command(command) = source else { return XCTFail("\(source)") }
        XCTAssertEqual(command.keep, 200)
    }

    func testTargetShapesFollowTheCLI() throws {
        func target(_ value: WidgetValue) throws -> WidgetTarget? {
            try WidgetSourceReader.read(
                object(["kind": .string("session"), "session": .string("main"), "every": .string("2s"), "target": value]),
                scope: inline).target
        }
        XCTAssertEqual(try target(.object(["machine": .int(7)])), .machine("7"))
        XCTAssertEqual(try target(.object(["machine": .string("main"), "workspace": .string("")])), .machine("main"))
        XCTAssertEqual(try target(.object(["machine": .null, "workspace": .string("alice")])), .workspace("alice"))
        XCTAssertEqual(try target(.string("local")), .local)
        let base: [String: WidgetValue] = ["kind": .string("session"), "session": .string("main"), "every": .string("2s")]
        let refused: [(WidgetValue, String)] = [
            (.object(["machine": .string("main"), "workspace": .string("alice")]),
             "source.target names one machine or one workspace: write local, {machine: <name>} or {workspace: <name>}"),
            (.object(["machine": .string("")]),
             "source.target names one machine or one workspace: write local, {machine: <name>} or {workspace: <name>}"),
            (.object(["host": .string("main")]),
             "source.target has an unknown key \"host\": write local, {machine: <name>} or {workspace: <name>}"),
            (.object(["machine": .list([.string("main")])]),
             "source.target: write local, {machine: <name>} or {workspace: <name>}"),
            (.string(""), "source.target \"\": write local, {machine: <name>} or {workspace: <name>}"),
        ]
        for (value, message) in refused {
            var fields = base
            fields["target"] = value
            XCTAssertEqual(problem(fields)?.message, message, "\(value)")
        }
    }

    func testProviderRulesFollowTheCLI() {
        let usage: [String: WidgetValue] = [
            "kind": .string("provider"), "name": .string("app/harness-usage"),
            "with": .object(["harness": .string("claude")]), "every": .string("60s"),
        ]
        XCTAssertNil(problem(usage, scope: packageScope))
        func changed(_ key: String, _ value: WidgetValue?) -> [String: WidgetValue] {
            var fields = usage
            fields[key] = value
            return fields
        }
        let cases: [(String, [String: WidgetValue], [String], String)] = [
            ("unknown provider", changed("name", .string("app/weather")), ["name"],
             "source.name \"app/weather\" is not a provider engine 1.3 knows: app/clock, app/harness-usage, app/machines, "
                + "app/publish-port, app/session-context, app/shortcuts, app/summary, app/workspaces"),
            ("unknown argument", changed("with", .object(["harness": .string("claude"), "zone": .string("utc")])),
             ["with", "zone"], "source.with.zone is not an argument of app/harness-usage"),
            ("missing argument", changed("with", nil), ["with"], "source.with.harness is required by app/harness-usage"),
            ("inputs in a board", changed("with", .object(["harness": .string("{{inputs.harness}}")])),
             ["with", "harness"], "template {{inputs.harness}} in source.with.harness: a widget written in a board has no inputs"),
            ("no every", changed("every", nil), ["every"], "every widget needs source.every, at least 5s for app/harness-usage"),
            ("bad every", changed("every", .string("soon")), ["every"],
             "source.every \"soon\" is not a duration: write it like 60s or 5m"),
            ("below minimum", changed("every", .string("1s")), ["every"],
             "source.every 1s is below the app/harness-usage minimum of 5s"),
        ]
        for (name, fields, path, message) in cases {
            let found = problem(fields)
            XCTAssertEqual(found?.path, path, name)
            XCTAssertEqual(found?.message, message, name)
        }
    }

    func testTemplateWhitespaceIsASCIILikeGo() {
        let base: [String: WidgetValue] = ["kind": .string("command"), "run": .string("echo"), "every": .string("60s")]
        let scope = WidgetScope.inline(contextKeys: ["repo"])
        var tabs = base
        tabs["args"] = .list([.string("{{\tcontext.repo\n}}")])
        XCTAssertNil(problem(tabs, scope: scope))
        var nbsp = base
        nbsp["args"] = .list([.string("{{\u{00A0}context.repo}}")])
        XCTAssertEqual(
            problem(nbsp, scope: scope)?.message,
            "template {{\u{00A0}context.repo}} in source.args[0] names neither inputs.<name> nor context.<name>")
    }

    func testRunHoldsNoTemplateAndAShellLineTakesNoArgs() {
        let scope = WidgetScope.inline(contextKeys: ["repo"])
        let shellTemplate: [String: WidgetValue] = [
            "kind": .string("command"), "run": .string("cd \"{{context.repo}}\""), "shell": .bool(true), "every": .string("60s"),
        ]
        XCTAssertEqual(problem(shellTemplate, scope: scope)?.path, ["run"])
        XCTAssertEqual(problem(shellTemplate, scope: scope)?.message, ArgvBuilder.refusal(CommandSource(
            run: "cd \"{{context.repo}}\"", script: nil, args: [], shell: true, target: .local, every: .manual, timeout: 0,
            mode: .poll, keep: 0, parse: .text))?.message)
        let shellArgs: [String: WidgetValue] = [
            "kind": .string("command"), "run": .string("df"), "args": .list([.string("-h")]), "shell": .bool(true),
            "every": .string("60s"),
        ]
        XCTAssertEqual(problem(shellArgs, scope: scope)?.path, ["args"])
        let program: [String: WidgetValue] = ["kind": .string("command"), "run": .string("{{context.repo}}"), "every": .string("60s")]
        XCTAssertEqual(problem(program, scope: scope)?.path, ["run"])
        let fine: [String: WidgetValue] = [
            "kind": .string("command"), "run": .string("cd \"$DM_CONTEXT_REPO\" && git status"), "shell": .bool(true),
            "every": .string("60s"),
        ]
        XCTAssertNil(problem(fine, scope: scope))
        let argTemplate: [String: WidgetValue] = [
            "kind": .string("command"), "run": .string("ls"), "args": .list([.string("{{context.repo}}")]), "every": .string("60s"),
        ]
        XCTAssertNil(problem(argTemplate, scope: scope))
    }

    func testARunWithSpacesSaysWhatTheCLISays() {
        let spaced: [String: WidgetValue] = ["kind": .string("command"), "run": .string("df -h"), "every": .string("60s")]
        XCTAssertEqual(
            problem(spaced, scope: .inline(contextKeys: []))?.message,
            "source.run \"df -h\" has spaces: put each argument in source.args, or set shell: true to run it as a shell line")
    }

    func testARunWithoutShellRefusesAProgramEnvWouldMisread() {
        let scope = WidgetScope.inline(contextKeys: ["repo"])
        let dash: [String: WidgetValue] = ["kind": .string("command"), "run": .string("-i"), "every": .string("60s")]
        XCTAssertEqual(
            problem(dash, scope: scope)?.message,
            "source.run \"-i\" starts with -: a program name never does — name the program, and put options in source.args")
        let equals: [String: WidgetValue] = ["kind": .string("command"), "run": .string("A=b"), "every": .string("60s")]
        XCTAssertEqual(
            problem(equals, scope: scope)?.message,
            "source.run \"A=b\" has =: it reads as a variable to set, not a program — name the program, or set shell: true")
        for run in ["-i", "A=b", "--x", "/opt/a=b"] {
            let fields: [String: WidgetValue] = ["kind": .string("command"), "run": .string(run), "every": .string("60s")]
            XCTAssertEqual(problem(fields, scope: scope)?.path, ["run"], run)
            var remote = fields
            remote["target"] = .object(["machine": .string("main")])
            XCTAssertEqual(problem(remote, scope: scope)?.path, ["run"], run)
            var shell = fields
            shell["shell"] = .bool(true)
            XCTAssertNil(problem(shell, scope: .inline(contextKeys: ["repo"])), run)
        }
    }

    func testPackageWidgetsMayUseInputs() {
        let fields: [String: WidgetValue] = [
            "kind": .string("command"), "run": .string("df"), "every": .string("60s"),
            "target": .object(["machine": .string("{{inputs.machine}}")]),
        ]
        XCTAssertNil(problem(fields, scope: .package(inputs: ["machine"], contextKeys: [])))
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
