import XCTest
@testable import DevmachineCore

final class SourceRunnerTests: XCTestCase {
    private var launcher: FakeLauncher!
    private let cli = CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: ["SSH_AUTH_SOCK": "/tmp/a"])
    private let programs: Set<String> = ["/bin/df", "/usr/bin/printf", "/opt/acme/widgets/disk.sh", "/Users/alice/.local/bin/claude",
                                          "/Applications/Devmachine.app/zmx"]

    override func setUp() {
        launcher = FakeLauncher()
    }

    override func tearDown() {
        launcher.releaseAll()
    }

    private var environment: SourceRunEnvironment {
        let cli = self.cli
        let programs = self.programs
        return SourceRunEnvironment(
            cli: { cli }, localEnvironment: ["PATH": "/usr/bin:/bin", "DM_INPUT_STALE": "x"], home: "/Users/alice",
            isExecutable: { programs.contains($0) })
    }

    private func commandSource(
        _ target: WidgetTarget = .local, run: String? = "df", script: String? = nil, args: [String] = ["-h", "/"],
        shell: Bool = false, parse: ParseMode = .text, timeout: TimeInterval = 30
    ) -> WidgetSource {
        .command(CommandSource(run: run, script: script, args: args, shell: shell, target: target,
                               every: .interval(60), timeout: timeout, mode: .poll, keep: 200, parse: parse))
    }

    private func request(
        _ source: WidgetSource, view: String = "text", needsApproval: Bool = false, inputs: [String: String] = [:],
        package: String? = nil, packagePath: String? = nil, tail: Int? = nil, context: [String: String] = [:],
        approvals: WidgetApprovals = WidgetApprovals()
    ) -> SourceRunRequest {
        var widgetView = WidgetView(kind: view)
        widgetView.tail = tail
        let resolved = ResolvedSource(
            source: source, view: widgetView, every: source.every, needsApproval: needsApproval, package: package,
            packagePath: packagePath, inputs: inputs)
        return SourceRunRequest(instanceID: "w", source: resolved, context: context, approvals: approvals)
    }

    private func command(_ target: WidgetTarget = .local, parse: ParseMode = .text, timeout: TimeInterval = 30) -> SourceRunRequest {
        request(commandSource(target, parse: parse, timeout: timeout))
    }

    private func runner(sleep: @escaping SourceSleep = { _ in try await Task.sleep(for: .seconds(3600)) }) -> CommandSourceRunner {
        CommandSourceRunner(launcher: launcher, environment: environment, sleep: sleep)
    }

    private func output(_ work: () async throws -> SourceRunResult) async throws -> SourceOutput {
        let result = try await work()
        guard case let .output(output) = result else {
            XCTFail("expected output, got \(result)")
            return .text("")
        }
        return output
    }

    private func failure(_ work: () async throws -> SourceRunResult) async -> SourceError? {
        do {
            _ = try await work()
            return nil
        } catch let error as SourceError {
            return error
        } catch {
            XCTFail("unexpected \(error)")
            return nil
        }
    }

    func testALocalCommandRunsTheProgramFoundOnThePathAndParsesLines() async throws {
        launcher.stdout = Data("a\nb\n".utf8)
        let parsed = try await output { try await runner().fetch(command(parse: .lines)) }
        XCTAssertEqual(parsed, .lines(["a", "b"]))
        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.executable, "/bin/df")
        XCTAssertEqual(invocation.arguments, ["-h", "/"])
        XCTAssertEqual(invocation.currentDirectory, "/Users/alice")
        XCTAssertNil(invocation.environment?["DM_INPUT_STALE"])
    }

    func testAMachineCommandGoesThroughDevmachineRun() async throws {
        launcher.stdout = Data("ok".utf8)
        _ = try await runner().fetch(command(.machine("main")))
        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/devmachine")
        XCTAssertEqual(invocation.arguments, ["--machine", "main", "run", "--no-log", "--argv", "--", "df", "-h", "/"])
        XCTAssertEqual(invocation.environment, ["SSH_AUTH_SOCK": "/tmp/a"])
    }

    func testTemplatesAreFilledOnceWithTheAreasContext() async throws {
        let source = commandSource(.machine("{{context.machine}}"), run: "printf",
                                   args: ["%s", "{{inputs.label}}", "{{context.branch}}"])
        let sent = request(source, inputs: ["label": "{{context.branch}}"], context: ["machine": "main", "branch": "dev"])
        _ = try await runner().fetch(sent)
        XCTAssertEqual(launcher.invocations.first?.arguments,
                       ["--machine", "main", "run", "--no-log", "--argv", "--", "printf", "%s", "{{context.branch}}", "dev"])
    }

    func testATargetThatResolvesToNoNameCannotStart() async {
        let error = await failure { try await runner().fetch(request(commandSource(.machine("{{context.machine}}")))) }
        XCTAssertEqual(error, .cannotStart("the widget's target names no machine or workspace here"))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testALocalShellLineReadsValuesFromTheEnvironment() async throws {
        let source = commandSource(run: "df -h \"$DM_INPUT_PATH\" | tail -1", args: [], shell: true)
        _ = try await runner().fetch(request(source, inputs: ["path": "/; id"], context: ["branch": "dev"]))
        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.executable, "/bin/sh")
        XCTAssertEqual(invocation.arguments, ["-c", "df -h \"$DM_INPUT_PATH\" | tail -1"])
        XCTAssertEqual(invocation.environment?["DM_INPUT_PATH"], "/; id")
        XCTAssertNil(invocation.environment?["DM_CONTEXT_BRANCH"])
        XCTAssertNil(invocation.environment?["DM_INPUT_STALE"])
    }

    func testARemoteShellLineSendsTheValuesAsEnvWords() async throws {
        let source = commandSource(.workspace("alice"), run: "echo \"$DM_INPUT_NAME\"", args: [], shell: true)
        _ = try await runner().fetch(request(source, inputs: ["name": "bob"]))
        XCTAssertEqual(launcher.invocations.first?.arguments,
                       ["run", "--workspace", "alice", "--no-log", "--argv", "--",
                        "/usr/bin/env", "DM_INPUT_NAME=bob", "/bin/sh", "-c", "echo \"$DM_INPUT_NAME\""])
    }

    func testARefusedCommandNeverStarts() async {
        let source = commandSource(run: "{{inputs.tool}}", args: [])
        let error = await failure { try await runner().fetch(request(source, inputs: ["tool": "rm"])) }
        guard case .refused? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testAnUnapprovedCommandWaitsWithTheHashOfWhatWouldRun() async throws {
        let source = commandSource(run: "echo \"$DM_CONTEXT_BRANCH\"", args: [], shell: true)
        let sent = request(source, needsApproval: true, context: ["branch": "dev"])
        let hash = try XCTUnwrap(ApprovalSubject.hash(for: sent.source, context: ["branch": "dev"]))
        let result = try await runner().fetch(sent)
        XCTAssertEqual(result, .needsApproval(.waiting(hash: hash)))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testADeniedCommandNeverRuns() async throws {
        let source = commandSource()
        let unapproved = request(source, needsApproval: true)
        let hash = try XCTUnwrap(ApprovalSubject.hash(for: unapproved.source, context: [:]))
        var approvals = WidgetApprovals()
        approvals.record(.denied, hash: hash, summary: "df", at: Date(timeIntervalSince1970: 0))
        let result = try await runner().fetch(request(source, needsApproval: true, approvals: approvals))
        XCTAssertEqual(result, .needsApproval(.denied(hash: hash)))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testAnApprovalCoversOnlyTheValuesItWasGivenFor() async throws {
        let source = commandSource(run: "echo \"$DM_CONTEXT_BRANCH\"", args: [], shell: true)
        let approvedFor = request(source, needsApproval: true, context: ["branch": "dev"])
        let hash = try XCTUnwrap(ApprovalSubject.hash(for: approvedFor.source, context: ["branch": "dev"]))
        var approvals = WidgetApprovals()
        approvals.record(.allowed, hash: hash, summary: "echo", at: Date(timeIntervalSince1970: 0))

        launcher.stdout = Data("dev\n".utf8)
        let ran = try await output {
            try await runner().fetch(request(source, needsApproval: true, context: ["branch": "dev"], approvals: approvals))
        }
        XCTAssertEqual(ran, .text("dev"))

        let other = try await runner().fetch(
            request(source, needsApproval: true, context: ["branch": "main; id"], approvals: approvals))
        guard case let .needsApproval(.waiting(otherHash)) = other else { return XCTFail("\(other)") }
        XCTAssertNotEqual(otherHash, hash)
        XCTAssertEqual(launcher.invocations.count, 1)
    }

    func testALocalPackageScriptRunsFromThePackageFolder() async throws {
        let source = commandSource(run: nil, script: "disk.sh", args: ["{{inputs.path}}"])
        _ = try await runner().fetch(request(source, inputs: ["path": "/"], package: "acme", packagePath: "/opt/acme/widgets/"))
        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/acme/widgets/disk.sh")
        XCTAssertEqual(invocation.arguments, ["/"])
    }

    func testALocalPackageScriptWithoutAFolderOrExecBitCannotStart() async {
        let source = commandSource(run: nil, script: "disk.sh", args: [])
        let noFolder = await failure { try await runner().fetch(request(source, package: "acme", packagePath: nil)) }
        guard case .cannotStart? = noFolder else { return XCTFail("\(String(describing: noFolder))") }
        let notExecutable = await failure { try await runner().fetch(request(source, package: "acme", packagePath: "/opt/bob")) }
        XCTAssertEqual(notExecutable, .cannotStart("/opt/bob/disk.sh is not an executable file"))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testALocalPackageScriptThatLinksOutsideThePackageIsRefused() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("escape.sh").path, withDestinationPath: "/bin/df")
        try Data("#!/bin/sh\n".utf8).write(to: folder.appendingPathComponent("bin/real.sh"))
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("inside.sh").path, withDestinationPath: "bin/real.sh")
        let runner = CommandSourceRunner(
            launcher: launcher,
            environment: SourceRunEnvironment(cli: { throw SourceError.cannotStart("no CLI") }, localEnvironment: [:],
                                              home: "/Users/alice", isExecutable: { _ in true }))

        let escaped = await failure {
            try await runner.fetch(request(commandSource(run: nil, script: "escape.sh", args: []), package: "acme", packagePath: folder.path))
        }
        XCTAssertEqual(escaped, .refused("script escape.sh leads outside the package through a link"))
        XCTAssertTrue(launcher.invocations.isEmpty)

        _ = try await runner.fetch(request(commandSource(run: nil, script: "inside.sh", args: []), package: "acme", packagePath: folder.path))
        XCTAssertEqual(launcher.invocations.count, 1)
    }

    func testARemotePackageScriptGoesThroughRunPackage() async throws {
        let source = commandSource(.machine("main"), run: nil, script: "disk.sh", args: ["/"])
        _ = try await runner().fetch(request(source, package: "acme", packagePath: "/opt/acme/widgets"))
        XCTAssertEqual(launcher.invocations.first?.arguments,
                       ["--machine", "main", "run", "--no-log", "--package", "acme", "--script", "disk.sh", "--", "/"])
    }

    func testAProgramMissingFromThePathCannotStart() async {
        let error = await failure { try await runner().fetch(request(commandSource(run: "nope"))) }
        XCTAssertEqual(error, .cannotStart("nope was not found on this Mac"))
    }

    func testAFailedCommandKeepsItsStatusAndStderr() async {
        launcher.status = 3
        launcher.stderr = "df: /nope: No such file\n"
        let error = await failure { try await runner().fetch(command(.machine("main"))) }
        XCTAssertEqual(error, .exited(status: 3, stderr: "df: /nope: No such file"))
        XCTAssertEqual(error?.title, "It exited with 3")
    }

    func testExit255NamesTheCLIsErrorLine() async {
        launcher.status = 255
        launcher.stderr = "some ssh noise\nerror: machine \"ghost\" is not in config.yml\n"
        let error = await failure { try await runner().fetch(command(.machine("ghost"))) }
        XCTAssertEqual(error, .neverRan("machine \"ghost\" is not in config.yml"))
    }

    func testALocalExit255IsTheCommandsOwnCode() async {
        launcher.status = 255
        let error = await failure { try await runner().fetch(command()) }
        XCTAssertEqual(error, .exited(status: 255, stderr: ""))
    }

    func testAnOlderCLIAsksForAnUpdate() async {
        launcher.status = 1
        launcher.stderr = "Error: unknown flag: --argv\nUsage:\n  devmachine run [flags]\n"
        let error = await failure { try await runner().fetch(command(.machine("main"))) }
        guard case .needsNewerCLI? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(error?.title, "This needs a newer devmachine CLI")
    }

    func testALocalExit1IsJustAnExit() async {
        launcher.status = 1
        launcher.stderr = "unknown flag: --x"
        let error = await failure { try await runner().fetch(command()) }
        XCTAssertEqual(error, .exited(status: 1, stderr: "unknown flag: --x"))
    }

    func testATimeoutStopsTheProcess() async {
        launcher.holds = true
        let error = await failure { try await runner(sleep: { _ in }).fetch(command(timeout: 30)) }
        XCTAssertEqual(error, .timedOut(30))
        XCTAssertEqual(error?.title, "Timed out after 30s")
        XCTAssertTrue(launcher.processes.first?.isTerminated ?? false)
    }

    func testCancellingTheFetchStopsTheProcess() async throws {
        launcher.holds = true
        let runner = self.runner()
        let sent = command()
        let task = Task { try await runner.fetch(sent) }
        while launcher.processes.isEmpty { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled fetch should throw")
        } catch is CancellationError {
        }
        XCTAssertTrue(launcher.processes.first?.isTerminated ?? false)
    }

    func testTooMuchOutputIsAnError() async {
        launcher.stdout = Data(repeating: 0x61, count: OutputParser.maxBytes + 1)
        let error = await failure { try await runner().fetch(command()) }
        XCTAssertEqual(error, .unreadable("it printed more than 1 MB"))
        XCTAssertTrue(launcher.processes.first?.isTerminated ?? false)
    }

    func testAParseFailureIsUnreadable() async {
        launcher.stdout = Data("lots".utf8)
        let error = await failure { try await runner().fetch(command(parse: .number)) }
        XCTAssertEqual(error, .unreadable("expected a number, got \"lots\""))
    }

    func testALaunchFailureCannotStart() async {
        launcher.launchError = CocoaError(.fileNoSuchFile)
        let error = await failure { try await runner().fetch(command()) }
        guard case let .cannotStart(message)? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertTrue(message.hasPrefix("/bin/df: "), message)
    }

    func testAMissingCLICannotStart() async {
        let runner = CommandSourceRunner(
            launcher: launcher,
            environment: SourceRunEnvironment(cli: { throw SourceError.cannotStart("Devmachine CLI was not found") },
                                              localEnvironment: [:], home: "/Users/alice"))
        let error = await failure { try await runner.fetch(command(.machine("main"))) }
        XCTAssertEqual(error, .cannotStart("Devmachine CLI was not found"))
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testURLStatusMeasuresLatency() async throws {
        let clock = SteppingClock([Date(timeIntervalSinceReferenceDate: 0), Date(timeIntervalSinceReferenceDate: 0.084)])
        let runner = URLSourceRunner(client: FakeHTTPClient(status: 503), clock: { clock.next() })
        let parsed = try await output {
            try await runner.fetch(request(.url(URLSource(url: "https://example.com/health", every: .interval(30), timeout: 30, parse: .status))))
        }
        XCTAssertEqual(parsed, .status(code: 503, latency: 0.084))
    }

    func testURLTextNeedsASuccessAndJSONIsParsed() async throws {
        func url(_ parse: ParseMode, _ address: String = "https://example.com/x") -> SourceRunRequest {
            request(.url(URLSource(url: address, every: .interval(30), timeout: 30, parse: parse)), context: ["host": "example.com"])
        }
        let failing = URLSourceRunner(client: FakeHTTPClient(status: 404, body: Data("missing".utf8)))
        let notFound = await failure { try await failing.fetch(url(.text)) }
        XCTAssertEqual(notFound, .http("the page answered HTTP 404"))
        let json = URLSourceRunner(client: FakeHTTPClient(status: 200, body: Data(#"{"up": true}"#.utf8)))
        let parsed = try await output { try await json.fetch(url(.json, "https://{{context.host}}/x")) }
        XCTAssertEqual(parsed, .json(.object(["up": .bool(true)])))
        let refused = await failure { try await json.fetch(url(.text, "file:///etc/hosts")) }
        XCTAssertEqual(refused, .unreadable("file:///etc/hosts is not a web address"))
        let slow = URLSourceRunner(client: FakeHTTPClient(error: URLError(.timedOut)))
        let timedOut = await failure { try await slow.fetch(url(.status)) }
        XCTAssertEqual(timedOut, .timedOut(30))
    }

    func testAWebAddressIsFilledLikeTheRunFillsIt() throws {
        func web(_ address: String, inputs: [String: String] = [:]) -> ResolvedSource {
            ResolvedSource(source: .url(URLSource(url: address, every: .interval(30), timeout: 30, parse: .status)),
                           view: WidgetView(kind: "web"), every: .interval(30), needsApproval: false, package: "mine",
                           packagePath: nil, inputs: inputs, contextKeys: [])
        }
        XCTAssertEqual(try URLSourceRunner.address(of: web("https://{{inputs.host}}/", inputs: ["host": "example.com"]), context: [:]),
                       URL(string: "https://example.com/"))
        XCTAssertThrowsError(try URLSourceRunner.address(of: web("{{inputs.host}}", inputs: ["host": "file:///etc/hosts"]), context: [:])) {
            XCTAssertEqual($0 as? SourceError, .unreadable("file:///etc/hosts is not a web address"))
        }
    }

    private func prompt(_ harness: PromptHarness, _ text: String, _ target: WidgetTarget, needsApproval: Bool = false,
                        approvals: WidgetApprovals = WidgetApprovals()) -> SourceRunRequest {
        request(.prompt(PromptSource(harness: harness, prompt: text, target: target, every: .manual, timeout: 300)),
                needsApproval: needsApproval, approvals: approvals)
    }

    func testALocalPromptRunsTheFoundHarnessWithItsFolderFirst() async throws {
        launcher.stdout = Data("# Today\n- one\n".utf8)
        let runner = PromptSourceRunner(launcher: launcher, environment: environment,
                                        locateHarness: { _ in "/Users/alice/.local/bin/claude" })
        let parsed = try await output { try await runner.fetch(prompt(.claude, "--help", .local)) }
        XCTAssertEqual(parsed, .text("# Today\n- one"))
        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.executable, "/Users/alice/.local/bin/claude")
        XCTAssertEqual(invocation.arguments, ["-p", "--", "--help"])
        XCTAssertTrue(invocation.environment?["PATH"]?.hasPrefix("/Users/alice/.local/bin:") ?? false)
        XCTAssertEqual(invocation.currentDirectory, "/Users/alice")
    }

    func testACodexPromptOnAWorkspace() async throws {
        let runner = PromptSourceRunner(launcher: launcher, environment: environment, locateHarness: { _ in nil })
        _ = try await runner.fetch(prompt(.codex, "Hi", .workspace("alice")))
        XCTAssertEqual(launcher.invocations.first?.arguments,
                       ["run", "--workspace", "alice", "--no-log", "--argv", "--", "codex", "exec", "--skip-git-repo-check", "--", "Hi"])
    }

    func testAPromptWaitsForApproval() async throws {
        let runner = PromptSourceRunner(launcher: launcher, environment: environment, locateHarness: { _ in nil })
        let result = try await runner.fetch(prompt(.claude, "Hi", .machine("main"), needsApproval: true))
        guard case .needsApproval(.waiting) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testAPromptTimesOutAtItsOwnTimeout() async {
        launcher.holds = true
        let runner = PromptSourceRunner(launcher: launcher, environment: environment, locateHarness: { _ in nil }, sleep: { _ in })
        let error = await failure { try await runner.fetch(prompt(.claude, "Hi", .machine("main"))) }
        XCTAssertEqual(error, .timedOut(300))
    }

    func testAMissingHarnessCannotStart() async {
        let runner = PromptSourceRunner(launcher: launcher, environment: environment, locateHarness: { _ in nil })
        let error = await failure { try await runner.fetch(prompt(.claude, "Hi", .local)) }
        XCTAssertEqual(error, .cannotStart("claude was not found on this Mac"))
    }

    func testARemoteSessionCapturesThePaneAndKeepsTheTail() async throws {
        launcher.stdout = Data((1...300).map { "line \($0)" }.joined(separator: "\n").appending("\n\n\n").utf8)
        let runner = SessionSourceRunner(launcher: launcher, environment: environment, zmxPath: { nil })
        let parsed = try await output {
            try await runner.fetch(request(.session(SessionSource(target: .machine("main"), session: "main", every: .interval(2))),
                                           view: "terminal", tail: 40))
        }
        XCTAssertEqual(launcher.invocations.first?.arguments,
                       ["--machine", "main", "run", "--no-log", "--argv", "--", "tmux", "capture-pane", "-p", "-e", "-t", "main"])
        guard case let .ansi(text) = parsed else { return XCTFail("\(parsed)") }
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 40)
        XCTAssertEqual(lines.last, "line 300")
    }

    func testALocalSessionReadsZmxHistory() async throws {
        launcher.stdout = Data("prompt$ \n".utf8)
        let runner = SessionSourceRunner(launcher: launcher, environment: environment, zmxPath: { "/Applications/Devmachine.app/zmx" })
        _ = try await runner.fetch(request(.session(SessionSource(target: .local, session: "{{context.session}}", every: .interval(2))),
                                           context: ["session": "shell"]))
        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.executable, "/Applications/Devmachine.app/zmx")
        XCTAssertEqual(invocation.arguments, ["history", "shell", "--vt"])
        XCTAssertEqual(invocation.environment?["ZMX_DIR"], Zmx.socketDirectory())
        XCTAssertEqual(invocation.environment?["HOME"], "/Users/alice")
        XCTAssertNil(invocation.environment?["DM_INPUT_STALE"])
    }

    func testALocalSessionNameThatLooksLikeAnOptionIsRefused() async {
        let runner = SessionSourceRunner(launcher: launcher, environment: environment, zmxPath: { "/Applications/Devmachine.app/zmx" })
        let error = await failure {
            try await runner.fetch(request(.session(SessionSource(target: .local, session: "--all", every: .interval(2)))))
        }
        guard case .refused? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertTrue(launcher.invocations.isEmpty)
    }

    func testASessionWaitsForApproval() async throws {
        let runner = SessionSourceRunner(launcher: launcher, environment: environment, zmxPath: { nil })
        let result = try await runner.fetch(
            request(.session(SessionSource(target: .machine("main"), session: "main", every: .interval(2))), needsApproval: true))
        guard case .needsApproval(.waiting) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(launcher.invocations.isEmpty)
    }
}
