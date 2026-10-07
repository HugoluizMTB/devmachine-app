import XCTest
@testable import DevmachineCore

final class ArgvBuilderTests: XCTestCase {
    private let cli = CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: ["SSH_AUTH_SOCK": "/tmp/a"])
    private let home = "/Users/alice"
    private let attacks = [
        "x; rm -rf ~", "'; id; '", "$(id)", "`id`", "a\nid", "a'b", "a\"b", "a\\b", "&& id", "| id", "> /tmp/x", "$HOME", "-h", "",
    ]

    private func command(
        run: String? = "df", script: String? = nil, args: [String] = [], shell: Bool = false, target: WidgetTarget = .local
    ) -> CommandSource {
        CommandSource(run: run, script: script, args: args, shell: shell, target: target, every: .interval(60),
                      timeout: 30, mode: .poll, keep: 200, parse: .text)
    }

    private func onlyUsrBin(_ path: String) -> Bool { path.hasPrefix("/usr/bin/") }

    func testShellSyntaxInAnArgumentStaysOneWord() throws {
        let words = try ArgvBuilder.command(command(args: ["-h", "x; rm -rf ~", "$(id)"]), package: nil, packagePath: nil)
        XCTAssertEqual(words, .argv(["df", "-h", "x; rm -rf ~", "$(id)"]))
        XCTAssertEqual(
            ArgvBuilder.remote(words, target: .machine("main"), cli: cli)?.arguments,
            ["--machine", "main", "run", "--no-log", "--argv", "--", "df", "-h", "x; rm -rf ~", "$(id)"])
        XCTAssertEqual(
            ArgvBuilder.local(words, environment: [:], home: home, isExecutable: onlyUsrBin)?.arguments,
            ["-h", "x; rm -rf ~", "$(id)"])
    }

    func testAWorkspaceGoesAfterRun() throws {
        let invocation = ArgvBuilder.remote(.argv(["df"]), target: .workspace("alice"), cli: cli)
        XCTAssertEqual(invocation?.executable, "/opt/homebrew/bin/devmachine")
        XCTAssertEqual(invocation?.arguments, ["run", "--workspace", "alice", "--no-log", "--argv", "--", "df"])
        XCTAssertEqual(invocation?.environment, ["SSH_AUTH_SOCK": "/tmp/a"])
        XCTAssertNil(ArgvBuilder.remote(.argv(["df"]), target: .local, cli: cli))
    }

    func testVariableNames() {
        XCTAssertEqual(TemplateValues.variableName("DM_INPUT_", "path"), "DM_INPUT_PATH")
        XCTAssertEqual(TemplateValues.variableName("DM_INPUT_", "max-load"), "DM_INPUT_MAX_LOAD")
        XCTAssertEqual(TemplateValues.variableName("DM_CONTEXT_", "workspace.name"), "DM_CONTEXT_WORKSPACE_NAME")
        XCTAssertEqual(TemplateValues.variableName("DM_INPUT_", "a b$é9"), "DM_INPUT_A_B__9")
        let values = TemplateValues(inputs: ["path": "/", "max-load": "3"], context: ["workspace.name": "alice"])
        XCTAssertEqual(values.environment, [
            "DM_INPUT_PATH": "/", "DM_INPUT_MAX_LOAD": "3", "DM_CONTEXT_WORKSPACE_NAME": "alice",
        ])
    }

    func testVariableNamesMatchTheCLIsEnvName() {
        let cases = [
            "inputs.disk-path": "DM_INPUT_DISK_PATH", "inputs.machine": "DM_INPUT_MACHINE", " inputs.max_lines ": "DM_INPUT_MAX_LINES",
            "context.workspace.name": "DM_CONTEXT_WORKSPACE_NAME", "context.project": "DM_CONTEXT_PROJECT",
        ]
        for (reference, name) in cases { XCTAssertEqual(TemplateValues.variableName(reference: reference), name, reference) }
        for reference in ["item.name", "inputs", "inputs.", "machine"] { XCTAssertNil(TemplateValues.variableName(reference: reference)) }
        XCTAssertEqual(TemplateValues.variableName("DM_INPUT_", "straße"), "DM_INPUT_STRA_E")
    }

    func testTheCLIsRefusalWords() {
        func refusal(_ run: String, args: [String] = [], shell: Bool = true) -> (field: String, message: String)? {
            ArgvBuilder.refusal(command(run: run, args: args, shell: shell))
        }
        XCTAssertEqual(refusal("echo {{inputs.machine}}")?.message,
                       "source.run is a shell line, so it cannot hold {{inputs.machine}}: read it as \"$DM_INPUT_MACHINE\" instead")
        XCTAssertEqual(refusal("echo '{{ context.project }}'")?.message,
                       "source.run is a shell line, so it cannot hold {{ context.project }}: read it as \"$DM_CONTEXT_PROJECT\" instead")
        XCTAssertEqual(refusal("echo {{item.name}}")?.message,
                       "source.run is a shell line, so it cannot hold {{item.name}}: read values as $DM_INPUT_<NAME> or $DM_CONTEXT_<KEY> instead")
        XCTAssertEqual(refusal("df", args: ["-h"])?.message,
                       "a shell line takes no source.args: write the words in source.run, and read values as $DM_INPUT_<NAME>")
        XCTAssertEqual(refusal("{{inputs.prog}}", shell: false)?.message,
                       "source.run cannot hold {{inputs.prog}}: a value must not pick the program — name the program in run, "
                           + "and put the value in source.args")
        XCTAssertNil(refusal("df -h -- \"$DM_INPUT_MACHINE\""))
    }

    func testAShellLineReadsItsValuesFromTheEnvironment() throws {
        let values = TemplateValues(inputs: ["path": "/; id"], context: ["workspace.name": "alice"])
        let built = try ArgvBuilder.command(command(run: "df \"$DM_INPUT_PATH\" | tail -1", shell: true), values: values,
                                            package: nil, packagePath: nil)
        let environment = ["DM_INPUT_PATH": "/; id", "DM_CONTEXT_WORKSPACE_NAME": "alice"]
        XCTAssertEqual(built, .shell(line: "df \"$DM_INPUT_PATH\" | tail -1", environment: environment))
        XCTAssertEqual(ArgvBuilder.remote(built, target: .machine("main"), cli: cli)?.arguments, [
            "--machine", "main", "run", "--no-log", "--argv", "--", "/usr/bin/env",
            "DM_CONTEXT_WORKSPACE_NAME=alice", "DM_INPUT_PATH=/; id", "/bin/sh", "-c", "df \"$DM_INPUT_PATH\" | tail -1",
        ])
        XCTAssertEqual(ArgvBuilder.remote(built, target: .workspace("alice"), cli: cli)?.arguments.prefix(6),
                       ["run", "--workspace", "alice", "--no-log", "--argv", "--"])
        let local = ArgvBuilder.local(built, environment: ["LANG": "C", "DM_INPUT_OLD": "stale"], home: home)
        XCTAssertEqual(local?.executable, "/bin/sh")
        XCTAssertEqual(local?.arguments, ["-c", "df \"$DM_INPUT_PATH\" | tail -1"])
        XCTAssertEqual(local?.currentDirectory, home)
        XCTAssertEqual(local?.environment?["DM_INPUT_PATH"], "/; id")
        XCTAssertEqual(local?.environment?["DM_CONTEXT_WORKSPACE_NAME"], "alice")
        XCTAssertEqual(local?.environment?["LANG"], "C")
        XCTAssertNil(local?.environment?["DM_INPUT_OLD"])
    }

    func testAShellLineSeesHostileValuesLiterallyThroughARealShell() throws {
        for attack in attacks {
            let built = try ArgvBuilder.command(
                command(run: "printf '%s|' \"$DM_INPUT_V\" $DM_CONTEXT_K", shell: true),
                values: TemplateValues(inputs: ["v": attack], context: ["k": "plain"]), package: nil, packagePath: nil)
            XCTAssertEqual(try printed(by: built), "\(attack)|plain|", attack)
        }
    }

    func testTheRemoteShellArgvHoldsEachValueAsOneWord() throws {
        for attack in attacks {
            let built = try ArgvBuilder.command(command(run: "echo \"$DM_INPUT_V\"", shell: true),
                                                values: TemplateValues(inputs: ["v": attack], context: [:]), package: nil, packagePath: nil)
            XCTAssertEqual(ArgvBuilder.remote(built, target: .machine("main"), cli: cli)?.arguments.suffix(5),
                           ["/usr/bin/env", "DM_INPUT_V=\(attack)", "/bin/sh", "-c", "echo \"$DM_INPUT_V\""], attack)
        }
    }

    func testTheEnvArgvAReachesAShellAsTheSameValue() throws {
        for attack in attacks {
            let built = try ArgvBuilder.command(command(run: "printf %s \"$DM_INPUT_V\"", shell: true),
                                                values: TemplateValues(inputs: ["v": attack], context: [:]), package: nil, packagePath: nil)
            guard let words = ArgvBuilder.remote(built, target: .machine("main"), cli: cli)?.arguments.drop(while: { $0 != "--" }).dropFirst()
            else { return XCTFail() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: words.first ?? "")
            process.arguments = Array(words.dropFirst())
            process.environment = [:]
            XCTAssertEqual(try output(of: process), attack, attack)
        }
    }

    func testAShellLineWithATemplateOrArgsBuildsNothing() {
        let cases = [
            command(run: "echo {{inputs.x}}", shell: true), command(run: "echo \"{{inputs.x}}\"", shell: true),
            command(run: "echo", args: ["{{inputs.x}}"], shell: true), command(run: "{{inputs.prog}}"),
        ]
        for source in cases {
            XCTAssertThrowsError(try ArgvBuilder.command(source, values: .none, package: nil, packagePath: nil)) { error in
                XCTAssertEqual(error as? WidgetCommandError, ArgvBuilder.refusal(source).map { .refused($0.message) })
            }
            XCTAssertThrowsError(try WidgetSource.command(source).resolved(with: .none))
        }
        XCTAssertEqual(ArgvBuilder.refusal(cases[0])?.field, "run")
        XCTAssertEqual(ArgvBuilder.refusal(cases[2])?.field, "args")
        XCTAssertNil(ArgvBuilder.refusal(command(run: "df", args: ["{{inputs.x}}"])))
    }

    func testTemplatesInArgsAreOneWordUnquoted() throws {
        let source = command(run: "df", args: ["{{inputs.path}}", "-x{{inputs.path}}"], target: .machine("{{inputs.machine}}"))
        let values = TemplateValues(inputs: ["path": "x; id", "machine": "main"], context: [:])
        guard case let .command(value) = try WidgetSource.command(source).resolved(with: values) else { return XCTFail() }
        XCTAssertEqual(value.args, ["x; id", "-xx; id"])
        XCTAssertEqual(value.target, .machine("main"))
        XCTAssertEqual(try ArgvBuilder.command(source, values: values, package: nil, packagePath: nil), .argv(["df", "x; id", "-xx; id"]))
    }

    func testContextAndMissingValues() throws {
        let values = TemplateValues(inputs: [:], context: ["workspace.name": "alice"])
        XCTAssertEqual(values.resolve("{{context.workspace.name}}/{{inputs.none}}"), "alice/")
    }

    func testPackageScripts() throws {
        let source = command(run: nil, script: "widgets/disk/check.sh", args: ["{{inputs.at}}"])
        let values = TemplateValues(inputs: ["at": "/"], context: [:])
        XCTAssertEqual(
            try ArgvBuilder.command(source, values: values, package: "mine", packagePath: "/Users/alice/.config/devmachine/packages/mine"),
            .argv(["/Users/alice/.config/devmachine/packages/mine/widgets/disk/check.sh", "/"]))
        var remote = source
        remote.target = .machine("main")
        let words = try ArgvBuilder.command(remote, values: values, package: "mine", packagePath: "/x")
        XCTAssertEqual(words, .packageScript(package: "mine", script: "widgets/disk/check.sh", args: ["/"]))
        XCTAssertEqual(ArgvBuilder.remote(words, target: .machine("main"), cli: cli)?.arguments,
                       ["--machine", "main", "run", "--no-log", "--package", "mine", "--script", "widgets/disk/check.sh", "--", "/"])
        XCTAssertNil(ArgvBuilder.local(words, environment: [:], home: home))
    }

    func testAnInlineScriptIsAnAbsolutePath() throws {
        let words = try ArgvBuilder.command(command(run: nil, script: "/opt/tools/check", args: ["a"], target: .machine("main")),
                                            package: nil, packagePath: nil)
        XCTAssertEqual(words, .argv(["/opt/tools/check", "a"]))
        let local = ArgvBuilder.local(words, environment: [:], home: home)
        XCTAssertEqual(local?.executable, "/opt/tools/check")
        XCTAssertEqual(local?.arguments, ["a"])
    }

    func testAProgramNameIsFoundOnThePATHAndStartedWithoutEnv() throws {
        var looked: [String] = []
        let local = ArgvBuilder.local(.argv(["df", "-h"]), environment: ["PATH": "/opt/x:/usr/bin", "LANG": "C"], home: home) {
            looked.append($0)
            return $0 == "/usr/bin/df"
        }
        XCTAssertEqual(looked, ["/opt/x/df", "/usr/bin/df"])
        XCTAssertEqual(local?.executable, "/usr/bin/df")
        XCTAssertEqual(local?.arguments, ["-h"])
        XCTAssertEqual(local?.currentDirectory, home)
        XCTAssertEqual(local?.environment?["LANG"], "C")
        XCTAssertEqual(local?.environment?["PATH"],
                       "/opt/x:/usr/bin:/Users/alice/.local/bin:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/sbin:/sbin")
        XCTAssertNil(ArgvBuilder.local(.argv(["nothere"]), environment: [:], home: home) { _ in false })
    }

    func testAValueLikeProgramNameIsOnlyAFileName() {
        var looked: [String] = []
        XCTAssertNil(ArgvBuilder.local(.argv(["-i", "id"]), environment: ["PATH": "/usr/bin"], home: home) {
            looked.append($0)
            return false
        })
        XCTAssertEqual(looked.first, "/usr/bin/-i")
        XCTAssertEqual(ArgvBuilder.local(.argv(["A=b"]), environment: [:], home: home) { $0 == "/usr/bin/A=b" }?.executable, "/usr/bin/A=b")
    }

    func testARealProgramRunsWithoutEnv() throws {
        let built = try ArgvBuilder.command(command(run: "printf", args: ["%s", "{{inputs.v}}"]),
                                            values: TemplateValues(inputs: ["v": "$(echo pwned)"], context: [:]),
                                            package: nil, packagePath: nil)
        guard let invocation = ArgvBuilder.local(built, environment: [:], home: NSTemporaryDirectory()) else { return XCTFail() }
        XCTAssertNotEqual(invocation.executable, "/usr/bin/env")
        XCTAssertTrue(invocation.executable.hasSuffix("/printf"))
        XCTAssertEqual(try printed(by: built), "$(echo pwned)")
    }

    func testPromptsAndSessions() throws {
        XCTAssertEqual(ArgvBuilder.prompt(PromptSource(harness: .claude, prompt: "Hi; id", target: .local, every: .manual, timeout: 300)),
                       .argv(["claude", "-p", "--", "Hi; id"]))
        XCTAssertEqual(ArgvBuilder.prompt(PromptSource(harness: .codex, prompt: "-h", target: .local, every: .manual, timeout: 300)),
                       .argv(["codex", "exec", "--skip-git-repo-check", "--", "-h"]))
        XCTAssertEqual(ArgvBuilder.tmuxCapture(session: "main; id"), .argv(["tmux", "capture-pane", "-p", "-e", "-t", "main; id"]))
    }

    func testInjectionAttemptsInArgsStayOneArgvItem() throws {
        for attack in attacks {
            let words = try ArgvBuilder.command(command(args: ["{{inputs.v}}"]),
                                                values: TemplateValues(inputs: ["v": attack], context: [:]), package: nil, packagePath: nil)
            XCTAssertEqual(words, .argv(["df", attack]), attack)
            XCTAssertEqual(ArgvBuilder.local(words, environment: [:], home: home, isExecutable: onlyUsrBin)?.arguments, [attack], attack)
            XCTAssertEqual(ArgvBuilder.remote(words, target: .workspace("alice"), cli: cli)?.arguments.last, attack, attack)
        }
    }

    func testTheApprovalHashCoversAShellLinesValues() throws {
        let shell = WidgetSource.command(command(run: "df \"$DM_INPUT_PATH\"", shell: true))
        let one = try ApprovalSubject.hash(shell, values: TemplateValues(inputs: ["path": "/"], context: [:]))
        let two = try ApprovalSubject.hash(shell, values: TemplateValues(inputs: ["path": "/home"], context: [:]))
        XCTAssertNotNil(one)
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(one, try ApprovalSubject.hash(shell, values: TemplateValues(inputs: ["path": "/"], context: [:])))
        XCTAssertTrue(ApprovalSubject.canonicalJSON(shell, environment: ["DM_INPUT_PATH": "/"])?.contains(#""env":{"DM_INPUT_PATH":"/"}"#) ?? false)
        let argv = WidgetSource.command(command(args: ["{{inputs.path}}"]))
        XCTAssertNotEqual(try ApprovalSubject.hash(argv, values: TemplateValues(inputs: ["path": "/"], context: [:])),
                          try ApprovalSubject.hash(argv, values: TemplateValues(inputs: ["path": "/home"], context: [:])))
        XCTAssertEqual(try ApprovalSubject.hash(argv, values: .none), ApprovalSubject.hash(.command(command(args: [""]))))
    }

    private func printed(by words: TargetCommand) throws -> String {
        guard let invocation = ArgvBuilder.local(words, environment: [:], home: NSTemporaryDirectory()) else {
            XCTFail("no invocation")
            return ""
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        return try output(of: process)
    }

    private func output(of process: Process) throws -> String {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text
    }

    func testNothingToRunBuildsNothing() {
        for source in [command(run: nil), command(run: ""), command(run: " ", shell: true)] {
            XCTAssertThrowsError(try ArgvBuilder.command(source, values: .none, package: nil, packagePath: nil)) { error in
                XCTAssertEqual(error as? WidgetCommandError, .nothingToRun)
            }
        }
    }

    func testTemplatesReachEveryField() throws {
        let values = TemplateValues(inputs: ["host": "example.com", "s": "main"], context: ["workspace.name": "alice"])
        let url = WidgetSource.url(URLSource(url: "https://{{inputs.host}}/x", every: .interval(60), timeout: 30, parse: .status))
        XCTAssertEqual(try url.resolved(with: values),
                       .url(URLSource(url: "https://example.com/x", every: .interval(60), timeout: 30, parse: .status)))
        let prompt = WidgetSource.prompt(PromptSource(harness: .claude, prompt: "{{ inputs.host }}",
                                                      target: .workspace("{{context.workspace.name}}"), every: .manual, timeout: 300))
        XCTAssertEqual(try prompt.resolved(with: values),
                       .prompt(PromptSource(harness: .claude, prompt: "example.com", target: .workspace("alice"),
                                            every: .manual, timeout: 300)))
        let session = WidgetSource.session(SessionSource(target: .machine("{{inputs.s}}"), session: "{{inputs.s}}", every: .interval(2)))
        XCTAssertEqual(try session.resolved(with: values),
                       .session(SessionSource(target: .machine("main"), session: "main", every: .interval(2))))
        let provider = WidgetSource.provider(ProviderSource(name: "http", with: ["url": "{{inputs.host}}"], every: "60s"))
        XCTAssertEqual(try provider.resolved(with: values),
                       .provider(ProviderSource(name: "http", with: ["url": "example.com"], every: "60s")))
    }

    func testLocalPATHKeepsTheInheritedOrderAndDropsRepeats() throws {
        XCTAssertEqual(LocalPATH.value(inherited: nil, home: home),
                       "/Users/alice/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(LocalPATH.value(inherited: "/opt/homebrew/bin::/x", home: home),
                       "/opt/homebrew/bin:/x:/Users/alice/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    func testAnEmptyArgvBuildsNothing() throws {
        XCTAssertNil(ArgvBuilder.local(.argv([]), environment: [:], home: home))
        XCTAssertNil(ArgvBuilder.local(.argv([""]), environment: [:], home: home))
    }

    func testNumbersReadTheWayTheCLIWritesThem() throws {
        XCTAssertEqual(WidgetValue.double(3.0).text, "3")
        XCTAssertEqual(WidgetValue.double(-2.0).text, "-2")
        XCTAssertEqual(WidgetValue.double(1.5).text, "1.5")
        XCTAssertEqual(WidgetValue.double(0.00001).text, "0.00001")
        XCTAssertEqual(WidgetValue.double(1e-7).text, "1e-7")
        XCTAssertEqual(WidgetValue.double(-2.5e-8).text, "-2.5e-8")
        XCTAssertEqual(WidgetValue.double(1.5e-10).text, "1.5e-10")
        XCTAssertEqual(WidgetValue.double(1.5e300).text, "1.5e+300")
        XCTAssertEqual(YAMLScalarStyle.number(1e-7), "1e-07")
        XCTAssertEqual(WidgetValue.double(1e16).text, "10000000000000000")
        XCTAssertEqual(WidgetValue.double(1e21).text, "1e+21")
        XCTAssertEqual(WidgetValue.double(0).text, "0")
        XCTAssertEqual(BoardScalar.double(3.0).text, "3")
        XCTAssertEqual(BoardScalar.double(0.00001).text, "0.00001")
        let values = TemplateValues(inputs: ["n": WidgetValue.double(3.0).text], context: [:])
        XCTAssertEqual(values.resolve("--depth={{inputs.n}}"), "--depth=3")
    }

    private func provider(
        _ name: String = "acme-tools/load", with: [String: String] = ["window": "5m"], target: WidgetTarget = .machine("main")
    ) -> PackageProviderSource {
        PackageProviderSource(name: name, with: with, target: target, every: .interval(30), timeout: 30)
    }

    func testAPackageProviderGoesThroughRunPackage() throws {
        let words = try ArgvBuilder.packageProvider(provider(with: ["window": "5m", "all": "yes"]))
        XCTAssertEqual(words, .packageCommand(package: "acme-tools", command: "load", args: ["--all", "yes", "--window", "5m"]))
        XCTAssertEqual(
            ArgvBuilder.remote(words, target: .machine("main"), cli: cli)?.arguments,
            ["--machine", "main", "run", "--no-log", "--package", "acme-tools", "--", "load", "--all", "yes", "--window", "5m"])
        XCTAssertEqual(
            ArgvBuilder.remote(words, target: .workspace("alice-dev"), cli: cli)?.arguments,
            ["run", "--workspace", "alice-dev", "--no-log", "--package", "acme-tools", "--", "load", "--all", "yes", "--window", "5m"])
        XCTAssertEqual(ArgvBuilder.remote(words, target: .machine("main"), cli: cli)?.environment, ["SSH_AUTH_SOCK": "/tmp/a"])
    }

    func testAPackageProviderWithNoWithIsTheCommandAlone() throws {
        XCTAssertEqual(try ArgvBuilder.packageProvider(provider(with: [:])),
                       .packageCommand(package: "acme-tools", command: "load", args: []))
    }

    func testAPackageProviderValueIsAlwaysOneWordAfterItsFlag() throws {
        for attack in attacks + ["--all", "--flag", "-rf", "--window=1", "{{context.machine}}"] {
            let words = try ArgvBuilder.packageProvider(provider(with: ["path": attack]))
            XCTAssertEqual(words, .packageCommand(package: "acme-tools", command: "load", args: ["--path", attack]), attack)
            XCTAssertEqual(
                ArgvBuilder.remote(words, target: .machine("main"), cli: cli)?.arguments.suffix(2),
                ["--path", attack], attack)
        }
    }

    func testABadNameOrFlagIsRefusedBeforeAnythingRuns() {
        for name in [
            "app/clock", "acme-tools", "acme-tools/load; rm -rf ~", "-x/load", "acme-tools/-rf", "acme-tools/--flag",
            "{{inputs.pkg}}/load", "acme-tools/{{inputs.cmd}}", "acme-tools/load\nid", "$(id)/load", "",
        ] {
            XCTAssertThrowsError(try ArgvBuilder.packageProvider(provider(name)), name) {
                guard case .refused? = $0 as? WidgetCommandError else { return XCTFail("\($0)") }
            }
        }
        XCTAssertThrowsError(try ArgvBuilder.packageProvider(provider(with: ["path": "a\u{0}b"]))) {
            XCTAssertEqual($0 as? WidgetCommandError, .refused("source.with.path holds a NUL byte"))
        }
        for key in ["x; rm", "-all", "All", "a b", "", "1st", "a\nb", "$(id)"] {
            XCTAssertThrowsError(try ArgvBuilder.packageProvider(provider(with: [key: "v"])), key) {
                guard case .refused? = $0 as? WidgetCommandError else { return XCTFail("\($0)") }
            }
        }
    }

    func testAPackageCommandNeverRunsOnThisMac() {
        XCTAssertNil(ArgvBuilder.local(
            .packageCommand(package: "acme-tools", command: "load", args: []), environment: [:], home: home))
        XCTAssertNil(ArgvBuilder.remote(.packageCommand(package: "acme-tools", command: "load", args: []), target: .local, cli: cli))
    }

    private func asked(_ harness: PromptHarness, _ mode: String?) -> TargetCommand {
        ArgvBuilder.prompt(PromptSource(harness: harness, prompt: "Hi; id", target: .local, every: .manual, timeout: 300,
                                        permissionMode: mode))
    }

    func testWithNoModeTheArgvIsTodaysByteForByte() {
        XCTAssertEqual(asked(.claude, nil), .argv(["claude", "-p", "--", "Hi; id"]))
        XCTAssertEqual(asked(.codex, nil), .argv(["codex", "exec", "--skip-git-repo-check", "--", "Hi; id"]))
    }

    func testEachModeBecomesItsHarnesssOwnFlag() {
        for mode in PermissionModes.names(for: "claude") {
            XCTAssertEqual(asked(.claude, mode), .argv(["claude", "-p", "--permission-mode", mode, "--", "Hi; id"]), mode)
        }
        let codex: [String: [String]] = [
            "read-only": ["--sandbox", "read-only"],
            "workspace-write": ["--sandbox", "workspace-write"],
            "danger-full-access": ["--sandbox", "danger-full-access"],
            "approve-for-me": ["--approve-for-me"],
            "dangerously-bypass-approvals-and-sandbox": ["--dangerously-bypass-approvals-and-sandbox"],
        ]
        XCTAssertEqual(Set(codex.keys), Set(PermissionModes.names(for: "codex")))
        for (mode, flags) in codex {
            XCTAssertEqual(asked(.codex, mode), .argv(["codex", "exec", "--skip-git-repo-check"] + flags + ["--", "Hi; id"]), mode)
        }
    }
}
