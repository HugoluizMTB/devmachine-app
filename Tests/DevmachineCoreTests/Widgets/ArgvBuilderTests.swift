import XCTest
@testable import DevmachineCore

final class ArgvBuilderTests: XCTestCase {
    private let cli = CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: ["SSH_AUTH_SOCK": "/tmp/a"])
    private let home = "/Users/alice"

    private func command(
        run: String? = "df", script: String? = nil, args: [String] = [], shell: Bool = false, target: WidgetTarget = .local
    ) -> CommandSource {
        CommandSource(run: run, script: script, args: args, shell: shell, target: target, every: .interval(60),
                      timeout: 30, mode: .poll, keep: 200, parse: .text)
    }

    func testShellSyntaxInAnArgumentStaysOneWord() {
        let words = ArgvBuilder.command(command(args: ["-h", "x; rm -rf ~", "$(id)"]), package: nil, packagePath: nil)
        XCTAssertEqual(words, .argv(["df", "-h", "x; rm -rf ~", "$(id)"]))
        XCTAssertEqual(
            ArgvBuilder.remote(words, target: .machine("main"), cli: cli)?.arguments,
            ["--machine", "main", "run", "--no-log", "--argv", "--", "df", "-h", "x; rm -rf ~", "$(id)"])
        XCTAssertEqual(
            ArgvBuilder.local(words, environment: [:], home: home)?.arguments, ["df", "-h", "x; rm -rf ~", "$(id)"])
    }

    func testAWorkspaceGoesAfterRun() {
        let invocation = ArgvBuilder.remote(.argv(["df"]), target: .workspace("alice"), cli: cli)
        XCTAssertEqual(invocation?.executable, "/opt/homebrew/bin/devmachine")
        XCTAssertEqual(invocation?.arguments, ["run", "--workspace", "alice", "--no-log", "--argv", "--", "df"])
        XCTAssertEqual(invocation?.environment, ["SSH_AUTH_SOCK": "/tmp/a"])
        XCTAssertNil(ArgvBuilder.remote(.argv(["df"]), target: .local, cli: cli))
    }

    func testShellTrueQuotesEveryArgument() {
        let line = ArgvBuilder.command(command(run: "df | tail -1", args: ["-h", "it's"], shell: true), package: nil, packagePath: nil)
        XCTAssertEqual(line, .shellLine("df | tail -1 '-h' 'it'\\''s'"))
        XCTAssertEqual(ArgvBuilder.remote(line, target: .machine("main"), cli: cli)?.arguments,
                       ["--machine", "main", "run", "--no-log", "--", "df | tail -1 '-h' 'it'\\''s'"])
        let local = ArgvBuilder.local(line, environment: [:], home: home)
        XCTAssertEqual(local?.executable, "/bin/sh")
        XCTAssertEqual(local?.arguments, ["-c", "df | tail -1 '-h' 'it'\\''s'"])
    }

    func testATemplatedValueInAShellLineIsQuoted() {
        let source = WidgetSource.command(command(run: "echo {{inputs.msg}}", shell: true))
        let resolved = source.resolved(with: TemplateValues(inputs: ["msg": "a; id"], context: [:]))
        guard case let .command(value) = resolved else { return XCTFail() }
        XCTAssertEqual(value.run, "echo 'a; id'")
    }

    func testATemplateWithoutShellIsOneWordUnquoted() {
        let source = WidgetSource.command(command(run: "{{inputs.prog}}", args: ["{{inputs.path}}"],
                                                  target: .machine("{{inputs.machine}}")))
        let resolved = source.resolved(with: TemplateValues(
            inputs: ["prog": "rm -rf", "path": "x; id", "machine": "main"], context: [:]))
        guard case let .command(value) = resolved else { return XCTFail() }
        XCTAssertEqual(value.run, "rm -rf")
        XCTAssertEqual(value.args, ["x; id"])
        XCTAssertEqual(value.target, .machine("main"))
        XCTAssertEqual(ArgvBuilder.command(value, package: nil, packagePath: nil), .argv(["rm -rf", "x; id"]))
    }

    func testContextAndMissingValues() {
        let values = TemplateValues(inputs: [:], context: ["workspace.name": "alice"])
        XCTAssertEqual(values.resolve("{{context.workspace.name}}/{{inputs.none}}"), "alice/")
    }

    func testPackageScripts() {
        let source = command(run: nil, script: "widgets/disk/check.sh", args: ["/"])
        XCTAssertEqual(ArgvBuilder.command(source, package: "mine", packagePath: "/Users/alice/.config/devmachine/packages/mine"),
                       .argv(["/Users/alice/.config/devmachine/packages/mine/widgets/disk/check.sh", "/"]))
        var remote = source
        remote.target = .machine("main")
        let words = ArgvBuilder.command(remote, package: "mine", packagePath: "/x")
        XCTAssertEqual(words, .packageScript(package: "mine", script: "widgets/disk/check.sh", args: ["/"]))
        XCTAssertEqual(ArgvBuilder.remote(words, target: .machine("main"), cli: cli)?.arguments,
                       ["--machine", "main", "run", "--no-log", "--package", "mine", "--script", "widgets/disk/check.sh", "--", "/"])
        XCTAssertNil(ArgvBuilder.local(words, environment: [:], home: home))
    }

    func testAnInlineScriptIsAnAbsolutePath() {
        let words = ArgvBuilder.command(command(run: nil, script: "/opt/tools/check", args: ["a"], target: .machine("main")),
                                        package: nil, packagePath: nil)
        XCTAssertEqual(words, .argv(["/opt/tools/check", "a"]))
        let local = ArgvBuilder.local(words, environment: [:], home: home)
        XCTAssertEqual(local?.executable, "/opt/tools/check")
        XCTAssertEqual(local?.arguments, ["a"])
    }

    func testAProgramNameRunsThroughEnvWithAFullPath() {
        let local = ArgvBuilder.local(.argv(["df", "-h"]), environment: ["PATH": "/usr/bin:/bin", "LANG": "C"], home: home)
        XCTAssertEqual(local?.executable, "/usr/bin/env")
        XCTAssertEqual(local?.arguments, ["df", "-h"])
        XCTAssertEqual(local?.currentDirectory, home)
        XCTAssertEqual(local?.environment?["LANG"], "C")
        XCTAssertEqual(local?.environment?["PATH"],
                       "/usr/bin:/bin:/Users/alice/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin")
    }

    func testPromptsAndSessions() {
        XCTAssertEqual(ArgvBuilder.prompt(PromptSource(harness: .claude, prompt: "Hi; id", target: .local, every: .manual, timeout: 300)),
                       .argv(["claude", "-p", "Hi; id"]))
        XCTAssertEqual(ArgvBuilder.prompt(PromptSource(harness: .codex, prompt: "Hi", target: .local, every: .manual, timeout: 300)),
                       .argv(["codex", "exec", "--skip-git-repo-check", "Hi"]))
        XCTAssertEqual(ArgvBuilder.tmuxCapture(session: "main; id"), .argv(["tmux", "capture-pane", "-p", "-e", "-t", "main; id"]))
    }

    func testInjectionAttemptsStayLiteral() {
        let attempts = ["x; rm -rf ~", "$(id)", "`id`", "a\nid", "a'b", "a\"b", "&& id", "| id", "> /tmp/x"]
        for attempt in attempts {
            let words = ArgvBuilder.command(command(args: [attempt]), package: nil, packagePath: nil)
            XCTAssertEqual(words, .argv(["df", attempt]), attempt)
            XCTAssertEqual(ArgvBuilder.local(words, environment: [:], home: home)?.arguments, ["df", attempt], attempt)
            XCTAssertEqual(ArgvBuilder.remote(words, target: .workspace("alice"), cli: cli)?.arguments.last, attempt, attempt)

            let line = ArgvBuilder.command(command(run: "echo", args: [attempt], shell: true), package: nil, packagePath: nil)
            XCTAssertEqual(line, .shellLine("echo " + RemoteCommands.shellSingleQuoted(attempt)), attempt)

            let source = WidgetSource.command(command(run: "echo {{inputs.v}}", shell: true))
            guard case let .command(value) = source.resolved(with: TemplateValues(inputs: ["v": attempt], context: [:])) else {
                return XCTFail()
            }
            XCTAssertEqual(value.run, "echo " + RemoteCommands.shellSingleQuoted(attempt), attempt)
        }
    }

    func testShellQuotedValuesComeBackLiteralFromARealShell() throws {
        let attempts = ["x; echo pwned", "$(echo pwned)", "`echo pwned`", "a\necho pwned", "it's", "\"q\"", "$HOME"]
        for attempt in attempts {
            let source = WidgetSource.command(command(run: "printf %s {{inputs.v}}", shell: true))
            guard case let .command(value) = source.resolved(with: TemplateValues(inputs: ["v": attempt], context: [:])),
                  let invocation = ArgvBuilder.local(
                      ArgvBuilder.command(value, package: nil, packagePath: nil), environment: [:], home: NSTemporaryDirectory())
            else { return XCTFail() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: invocation.executable)
            process.arguments = invocation.arguments
            process.environment = invocation.environment
            let output = Pipe()
            process.standardOutput = output
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            XCTAssertEqual(printed, attempt, attempt)
        }
    }

    func testTemplatesReachEveryField() {
        let values = TemplateValues(inputs: ["host": "example.com", "s": "main"], context: ["workspace.name": "alice"])
        let url = WidgetSource.url(URLSource(url: "https://{{inputs.host}}/x", every: .interval(60), timeout: 30, parse: .status))
        XCTAssertEqual(url.resolved(with: values),
                       .url(URLSource(url: "https://example.com/x", every: .interval(60), timeout: 30, parse: .status)))
        let prompt = WidgetSource.prompt(PromptSource(harness: .claude, prompt: "{{ inputs.host }}",
                                                      target: .workspace("{{context.workspace.name}}"), every: .manual, timeout: 300))
        XCTAssertEqual(prompt.resolved(with: values),
                       .prompt(PromptSource(harness: .claude, prompt: "example.com", target: .workspace("alice"),
                                            every: .manual, timeout: 300)))
        let session = WidgetSource.session(SessionSource(target: .machine("{{inputs.s}}"), session: "{{inputs.s}}", every: .interval(2)))
        XCTAssertEqual(session.resolved(with: values),
                       .session(SessionSource(target: .machine("main"), session: "main", every: .interval(2))))
        let provider = WidgetSource.provider(ProviderSource(name: "http", with: ["url": "{{inputs.host}}"], every: "60s"))
        XCTAssertEqual(provider.resolved(with: values),
                       .provider(ProviderSource(name: "http", with: ["url": "example.com"], every: "60s")))
    }

    func testLocalPATHKeepsTheInheritedOrderAndDropsRepeats() {
        XCTAssertEqual(LocalPATH.value(inherited: nil, home: home),
                       "/Users/alice/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(LocalPATH.value(inherited: "/opt/homebrew/bin::/x", home: home),
                       "/opt/homebrew/bin:/x:/Users/alice/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    func testAnEmptyArgvBuildsNothing() {
        XCTAssertNil(ArgvBuilder.local(.argv([]), environment: [:], home: home))
    }

    func testNumbersReadTheWayTheCLIWritesThem() {
        XCTAssertEqual(WidgetValue.double(3.0).text, "3")
        XCTAssertEqual(WidgetValue.double(-2.0).text, "-2")
        XCTAssertEqual(WidgetValue.double(1.5).text, "1.5")
        XCTAssertEqual(WidgetValue.double(0.00001).text, "0.00001")
        XCTAssertEqual(WidgetValue.double(1e-7).text, "1e-07")
        XCTAssertEqual(WidgetValue.double(1e16).text, "10000000000000000")
        XCTAssertEqual(WidgetValue.double(1e21).text, "1e+21")
        XCTAssertEqual(WidgetValue.double(0).text, "0")
        XCTAssertEqual(BoardScalar.double(3.0).text, "3")
        XCTAssertEqual(BoardScalar.double(0.00001).text, "0.00001")
        let values = TemplateValues(inputs: ["n": WidgetValue.double(3.0).text], context: [:])
        XCTAssertEqual(values.resolve("--depth={{inputs.n}}"), "--depth=3")
    }
}
