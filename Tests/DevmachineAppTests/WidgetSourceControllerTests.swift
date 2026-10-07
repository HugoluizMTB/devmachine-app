import Combine
import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class WidgetSourceControllerTests: XCTestCase {
    private var folder: URL!
    private var command: ScriptedSourceRunner!
    private var launcher: AppFakeLauncher!
    private var clock = Date(timeIntervalSince1970: 1_000)
    private var controller: WidgetSourceController!
    private var others: [WidgetSourceController] = []

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetSourceControllerTests-\(UUID().uuidString)")
        command = ScriptedSourceRunner()
        launcher = AppFakeLauncher()
        controller = makeController()
    }

    override func tearDown() async throws {
        controller.stop()
        others.forEach { $0.stop() }
        command.release()
        launcher.releaseAll()
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeController(
        isDemo: Bool = false, surface: String = "home", context: [String: String] = [:], runner: (any SourceRunner)? = nil
    ) -> WidgetSourceController {
        let environment = SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: [:]) },
            localEnvironment: [:], home: "/Users/alice", isExecutable: { _ in true })
        let command: any SourceRunner = runner ?? self.command
        let runners = SourceRunners(
            command: command, url: command, prompt: command, session: command, launcher: launcher, environment: environment)
        let made = WidgetSourceController(
            runners: runners, approvalsFile: WidgetApprovalsFile(fileURL: folder.appendingPathComponent("approvals.json")),
            historyStore: SparklineHistoryStore(directory: folder.appendingPathComponent("history")), surface: surface,
            context: context, isDemo: isDemo, startsTimer: false, now: { [unowned self] in self.clock })
        others.append(made)
        return made
    }

    private func entry(
        _ id: String = "disk", run: String = "df", every: WidgetEvery = .interval(60), inline: Bool = true,
        mode: CommandMode = .poll, view: String = "text", parse: ParseMode = .text, visible: Bool = true,
        target: WidgetTarget = .local, shell: Bool = false, args: [String] = []
    ) -> SourceWidgetEntry {
        let source = WidgetSource.command(CommandSource(
            run: run, script: nil, args: args, shell: shell, target: target, every: mode == .stream ? .continuous : every,
            timeout: 30, mode: mode, keep: 3, parse: parse))
        var widgetView = WidgetView(kind: view)
        if view == "sparkline" { widgetView.unit = "%" }
        return SourceWidgetEntry(id: id, source: ResolvedSource(
            source: source, view: widgetView, every: source.every, needsApproval: inline,
            package: inline ? nil : "mine", packagePath: nil), isVisible: visible)
    }

    func testTheTestsDriveTheTicksThemselves() {
        controller.start()
        XCTAssertFalse(controller.isTicking)
    }

    func testTheCardAndTheStoredSummaryShowWhatTheHashCovers() throws {
        let sidebar = makeController(surface: "sidebar", context: ["selected": "alice-dev"])
        sidebar.start()
        let listing = entry(run: "ls", args: ["{{context.selected}}"])
        sidebar.update([listing])
        XCTAssertEqual(sidebar.approvalPrompt(for: listing.source).what, "ls alice-dev")
        XCTAssertEqual(controller.approvalPrompt(for: listing.source).what, "ls ''")
        sidebar.approve("disk", hash: shown(sidebar, "disk"))
        let stored = try XCTUnwrap(sidebar.approvals.entries.values.first)
        XCTAssertEqual(stored.summary, "ls alice-dev on this Mac, every 1m")
        guard case let .success(hash?) = Result(catching: {
            try ApprovalSubject.hash(.command(CommandSource(
                run: "ls", script: nil, args: ["alice-dev"], shell: false, target: .local, every: .interval(60),
                timeout: 30, mode: .poll, keep: 3, parse: .text)), values: .none)
        }) else { return XCTFail() }
        XCTAssertNotNil(sidebar.approvals.entries[hash])
    }

    func testAWebWidgetLoadsItsAddressFilledFromItsInputs() {
        let web = ResolvedSource(
            source: .url(URLSource(url: "https://{{inputs.host}}/", every: .interval(60), timeout: 30, parse: .status)),
            view: WidgetView(kind: "web"), every: .interval(60), needsApproval: false, package: "mine", packagePath: nil,
            inputs: ["host": "example.com"], contextKeys: [])
        XCTAssertEqual(try controller.webAddress(for: web).get(), URL(string: "https://example.com/"))
        let blank = ResolvedSource(
            source: .url(URLSource(url: "{{inputs.host}}", every: .interval(60), timeout: 30, parse: .status)),
            view: WidgetView(kind: "web"), every: .interval(60), needsApproval: false, package: "mine", packagePath: nil)
        XCTAssertEqual(controller.webAddress(for: blank), .failure(.unreadable(" is not a web address")))
    }

    func testAnInlineCommandWaitsAndRunsNothing() async {
        controller.start()
        controller.update([entry()])
        controller.runNow("disk")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        guard case let .waiting(hash) = controller.approvalState("disk") else { return XCTFail() }
        XCTAssertFalse(hash.isEmpty)
    }

    func testAllowRunsItAndRemembersTheChoice() async {
        controller.start()
        controller.update([entry()])
        controller.approve("disk", hash: shown(controller, "disk"))
        await waitUntil { self.controller.state("disk").output == .text("ok") }
        XCTAssertEqual(command.calls, 1)
        XCTAssertEqual(command.requests.first?.approvals, controller.approvals)
        let again = makeController()
        again.update([entry()])
        XCTAssertEqual(again.approvalState("disk"), .allowed)
    }

    func testDenyKeepsItPaused() async {
        controller.start()
        controller.update([entry()])
        controller.deny("disk", hash: shown(controller, "disk"))
        clock = clock.addingTimeInterval(600)
        controller.tick()
        controller.runNow("disk")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        guard case .denied = controller.approvalState("disk") else { return XCTFail() }
    }

    func testAChangedCommandWaitsAgain() async {
        controller.start()
        controller.update([entry()])
        controller.approve("disk", hash: shown(controller, "disk"))
        await waitUntil { self.command.calls == 1 }
        controller.update([entry(run: "du")])
        guard case .waiting = controller.approvalState("disk") else { return XCTFail() }
        clock = clock.addingTimeInterval(600)
        controller.tick()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
    }

    func testAPackageWidgetRunsWithoutApproval() async {
        controller.start()
        controller.update([entry(inline: false)])
        await waitUntil { self.command.calls == 1 }
        XCTAssertEqual(controller.approvalState("disk"), .notNeeded)
    }

    func testHomeGivesNoContextAndOtherAreasOnlyTheirOwnKeys() async {
        controller.start()
        controller.update([entry(inline: false)])
        await waitUntil { self.command.calls == 1 }
        XCTAssertEqual(command.requests[0].context, [:])

        let sidebar = makeController(surface: "sidebar", context: ["selected": "alice-dev", "stray": "x"])
        sidebar.start()
        sidebar.update([entry("other", inline: false)])
        await waitUntil { self.command.calls == 2 }
        XCTAssertEqual(command.requests[1].context, ["selected": "alice-dev"])
    }

    func testAnAnswerThatNeedsApprovalPausesUntilApprovalsChange() async {
        command = ScriptedSourceRunner([.success(.needsApproval(.waiting(hash: "abc"))), .success(.output(.text("ok")))])
        controller = makeController()
        controller.start()
        controller.update([entry("pkg", every: .interval(5), inline: false), entry("disk")])
        await waitUntil { self.command.calls == 1 }
        await waitUntil { !self.controller.state("pkg").isRunning }
        clock = clock.addingTimeInterval(60)
        controller.tick()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
        controller.approve("disk", hash: shown(controller, "disk"))
        await waitUntil { self.command.calls == 3 }
        XCTAssertEqual(Set(command.requests.map(\.instanceID)), ["pkg", "disk"])
    }

    func testManualRunsOnlyOnRunNow() async {
        controller.start()
        controller.update([entry(every: .manual, inline: false)])
        clock = clock.addingTimeInterval(3600)
        controller.tick()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        controller.runNow("disk")
        await waitUntil { self.command.calls == 1 }
    }

    func testRunNowSkipsAMinimizedWidget() async {
        controller.start()
        controller.update([entry(every: .manual, inline: false, visible: false)])
        controller.runNow("disk")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        controller.update([entry(every: .manual, inline: false, visible: true)])
        controller.runNow("disk")
        await waitUntil { self.command.calls == 1 }
    }

    func testOneRunAtATime() async {
        command = ScriptedSourceRunner(gated: true)
        controller = makeController()
        controller.start()
        controller.update([entry(every: .interval(5), inline: false)])
        await waitUntil { self.command.calls == 1 }
        controller.runNow("disk")
        clock = clock.addingTimeInterval(60)
        controller.tick()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
        XCTAssertTrue(controller.state("disk").isRunning)
        command.release()
        await waitUntil { !self.controller.state("disk").isRunning }
    }

    func testAChangedSourceCancelsTheOldRunAndStartsTheNewOne() async {
        command = ScriptedSourceRunner(gated: true)
        controller = makeController()
        controller.start()
        controller.update([entry(every: .interval(60), inline: false)])
        await waitUntil { self.command.calls == 1 }
        controller.update([entry(run: "du", every: .interval(60), inline: false)])
        await waitUntil { self.command.calls == 2 }
        command.release()
        await waitUntil { self.controller.state("disk").output == .text("ok") }
        XCTAssertFalse(controller.state("disk").isRunning)
    }

    func testLeavingHomeCancelsARunningPoll() async {
        command = ScriptedSourceRunner(gated: true)
        controller = makeController()
        controller.start()
        controller.update([entry(every: .interval(60), inline: false)])
        await waitUntil { self.command.calls == 1 }
        controller.stop()
        XCTAssertFalse(controller.state("disk").isRunning)
        command.release()
        await waitUntil { self.command.cancelled == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(controller.state("disk").output)
        XCTAssertFalse(controller.state("disk").isRunning)
    }

    func testDenyCancelsARunningPoll() async {
        command = ScriptedSourceRunner(gated: true)
        controller = makeController()
        controller.start()
        controller.update([entry()])
        let hash = shown(controller, "disk")
        controller.approve("disk", hash: hash)
        await waitUntil { self.command.calls == 1 }
        controller.deny("disk", hash: hash)
        XCTAssertFalse(controller.state("disk").isRunning)
        command.release()
        await waitUntil { self.command.cancelled == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(controller.state("disk").output)
        guard case .denied = controller.approvalState("disk") else { return XCTFail() }
    }

    func testASourceWhoseHashCannotBeBuiltNeverRuns() async {
        controller.start()
        controller.update([entry(run: "echo hi", shell: true, args: ["x"])])
        controller.approve("disk", hash: shown(controller, "disk"))
        clock = clock.addingTimeInterval(600)
        controller.tick()
        controller.runNow("disk")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        XCTAssertEqual(controller.approvalState("disk"), .waiting(hash: ""))
        guard case .refused? = controller.state("disk").error else {
            return XCTFail("\(String(describing: controller.state("disk").error))")
        }
        XCTAssertTrue(controller.approvals.entries.isEmpty)
    }

    func testAnErrorKeepsTheLastGoodValue() async {
        command = ScriptedSourceRunner([.success(.output(.text("good"))), .failure(.timedOut(30))])
        controller = makeController()
        controller.start()
        controller.update([entry(every: .interval(5), inline: false)])
        await waitUntil { self.controller.state("disk").output == .text("good") }
        clock = clock.addingTimeInterval(5)
        controller.tick()
        await waitUntil { self.controller.state("disk").error == .timedOut(30) }
        XCTAssertEqual(controller.state("disk").output, .text("good"))
    }

    func testMinimizingAStreamStopsItAndShowingItStartsItAgain() async {
        controller.start()
        controller.update([entry("log", inline: false, mode: .stream)])
        await waitUntil { self.launcher.processes.count == 1 }
        launcher.write("a\nb\nc\nd\n")
        await waitUntil { self.controller.state("log").lines == ["b", "c", "d"] }
        controller.update([entry("log", inline: false, mode: .stream, visible: false)])
        XCTAssertTrue(launcher.processes[0].isTerminated)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(controller.state("log").error)
        XCTAssertFalse(controller.state("log").isRunning)
        controller.update([entry("log", inline: false, mode: .stream)])
        await waitUntil { self.launcher.processes.count == 2 }
    }

    func testARunningStreamIsNotRestartedByTicks() async {
        controller.start()
        controller.update([entry("log", inline: false, mode: .stream)])
        await waitUntil { self.launcher.processes.count == 1 }
        clock = clock.addingTimeInterval(600)
        controller.tick()
        controller.runNow("log")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(launcher.processes.count, 1)
        XCTAssertFalse(launcher.processes[0].isTerminated)
    }

    func testAnInlineStreamWaitsForItsApproval() async {
        controller.start()
        controller.update([entry("log", mode: .stream)])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(launcher.processes.count, 0)
        let hash = shown(controller, "log")
        controller.approve("log", hash: hash)
        await waitUntil { self.launcher.processes.count == 1 }
        controller.deny("log", hash: hash)
        XCTAssertTrue(launcher.processes[0].isTerminated)
    }

    func testLeavingHomeStopsStreamsAndComingBackRestartsThem() async {
        controller.start()
        controller.update([entry("log", inline: false, mode: .stream)])
        await waitUntil { self.launcher.processes.count == 1 }
        controller.stop()
        XCTAssertTrue(launcher.processes[0].isTerminated)
        controller.start()
        await waitUntil { self.launcher.processes.count == 2 }
    }

    func testAStreamThatEndedWaitsForThePlayButton() async {
        controller.start()
        controller.update([entry("log", inline: false, mode: .stream)])
        await waitUntil { self.launcher.processes.count == 1 }
        launcher.processes[0].finish(ProcessExit(status: 0, stderr: "", stoppedByCaller: false))
        await waitUntil { self.controller.state("log").ended }
        controller.tick()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(launcher.processes.count, 1)
        controller.runNow("log")
        await waitUntil { self.launcher.processes.count == 2 }
    }

    func testARemoteStreamGoesThroughTheCLI() async {
        controller.start()
        controller.update([entry("log", run: "journalctl", inline: false, mode: .stream, target: .machine("main"))])
        await waitUntil { self.launcher.processes.count == 1 }
        XCTAssertEqual(launcher.invocations[0].executable, "/opt/homebrew/bin/devmachine")
    }

    func testDemoModeRunsNothing() async {
        controller = makeController(isDemo: true)
        controller.start()
        controller.update([entry(inline: false), entry("log", inline: false, mode: .stream)])
        controller.runNow("disk")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
        XCTAssertEqual(launcher.processes.count, 0)
    }

    func testNothingRunsBeforeStart() async {
        controller.update([entry(inline: false)])
        controller.runNow("disk")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)
    }

    func testASparklineRecordsItsHistory() async {
        command = ScriptedSourceRunner([.success(.output(.number(42)))])
        controller = makeController()
        controller.start()
        controller.update([entry("load", inline: false, view: "sparkline", parse: .number)])
        await waitUntil { self.controller.history("load").count == 1 }
        let file = folder.appendingPathComponent("history/home-load.json")
        await waitUntil { FileManager.default.fileExists(atPath: file.path) }
        let reloaded = makeController()
        reloaded.update([entry("load", inline: false, view: "sparkline", parse: .number)])
        XCTAssertEqual(reloaded.history("load").map(\.value), [42])
    }

    private func contextEntry(_ id: String = "here", args: [String] = ["{{context.path}}"], inline: Bool = false, keys: Set<String>? = nil) -> SourceWidgetEntry {
        let source = WidgetSource.command(CommandSource(
            run: "ls", script: nil, args: args, shell: false, target: .local, every: .interval(60), timeout: 30,
            mode: .poll, keep: 3, parse: .text))
        return SourceWidgetEntry(id: id, source: ResolvedSource(
            source: source, view: WidgetView(kind: "text"), every: .interval(60), needsApproval: inline,
            package: inline ? nil : "mine", packagePath: nil, contextKeys: keys), isVisible: true)
    }

    func testASessionSwitchRerunsWithTheNewContext() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api", "stray": "x"])
        board.start()
        board.update([contextEntry()])
        await waitUntil { self.command.calls == 1 }
        XCTAssertEqual(command.requests[0].context["path"], "/home/alice/api")
        XCTAssertNil(board.context["stray"])
        await waitUntil { !board.state("here").isRunning }
        board.setContext(["path": "/home/alice/web"])
        await waitUntil { self.command.calls == 2 }
        XCTAssertEqual(command.requests[1].context["path"], "/home/alice/web")
    }

    func testAChangeToAKeyTheWidgetDoesNotReadChangesNothing() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api", "branch": "main"])
        board.start()
        board.update([contextEntry(keys: ["path"])])
        await waitUntil { self.command.calls == 1 }
        await waitUntil { board.state("here").output == .text("ok") }
        board.setContext(["path": "/home/alice/api", "branch": "feature"])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
        XCTAssertEqual(board.state("here").output, .text("ok"))
    }

    func testAnInlineWidgetIgnoresAChangeToAKeyItDoesNotRead() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api", "branch": "main"])
        board.start()
        board.update([contextEntry()])
        await waitUntil { self.command.calls == 1 }
        await waitUntil { board.state("here").output == .text("ok") }
        board.setContext(["path": "/home/alice/api", "branch": "feature"])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
        XCTAssertEqual(board.state("here").output, .text("ok"))
        board.setContext(["path": "/home/alice/web", "branch": "feature"])
        await waitUntil { self.command.calls == 2 }
    }

    func testAnApprovedInlineWidgetStaysApprovedWhenAnUnreadKeyChanges() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api", "branch": "main"])
        board.start()
        board.update([contextEntry(inline: true)])
        board.approve("here", hash: shown(board, "here"))
        await waitUntil { self.command.calls == 1 }
        await waitUntil { board.state("here").output == .text("ok") }
        board.setContext(["path": "/home/alice/api", "branch": "feature"])
        XCTAssertEqual(board.approvalState("here"), .allowed)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
    }

    func testAnInlineShellLineKeepsItsApprovalUntilAKeyItNamesChanges() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api", "branch": "main"])
        board.start()
        board.update([entry("here", run: "echo \"$DM_CONTEXT_PATH\"", shell: true)])
        board.approve("here", hash: shown(board, "here"))
        await waitUntil { self.command.calls == 1 }
        await waitUntil { board.state("here").output == .text("ok") }
        board.setContext(["path": "/home/alice/api", "branch": "feature"])
        XCTAssertEqual(board.approvalState("here"), .allowed)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 1)
        XCTAssertEqual(command.requests[0].source.values(context: command.requests[0].context).environment, [
            "DM_CONTEXT_PATH": "/home/alice/api",
        ])
        board.setContext(["path": "/home/alice/web", "branch": "feature"])
        guard case .waiting = board.approvalState("here") else { return XCTFail("\(board.approvalState("here"))") }
    }

    func testAnInlineScriptRerunsOnAnyKeyChange() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api", "branch": "main"])
        board.start()
        let source = WidgetSource.command(CommandSource(
            run: nil, script: "/home/alice/bin/status", args: [], shell: false, target: .local, every: .interval(60),
            timeout: 30, mode: .poll, keep: 3, parse: .text))
        board.update([SourceWidgetEntry(id: "status", source: ResolvedSource(
            source: source, view: WidgetView(kind: "text"), every: .interval(60), needsApproval: false,
            package: "mine", packagePath: nil), isVisible: true)])
        await waitUntil { self.command.calls == 1 }
        await waitUntil { !board.state("status").isRunning }
        board.setContext(["path": "/home/alice/api", "branch": "feature"])
        await waitUntil { self.command.calls == 2 }
    }

    func testASessionSwitchCancelsTheRunAndDropsItsAnswer() async {
        command = ScriptedSourceRunner([.success(.output(.text("files")))], gated: true)
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.start()
        board.update([contextEntry()])
        await waitUntil { self.command.calls == 1 }
        board.setContext(["path": "/home/alice/web"])
        await waitUntil { self.command.calls == 2 }
        command.release()
        await waitUntil { board.state("here").output == .text("files") }
        XCTAssertEqual(command.cancelled, 1)
        XCTAssertEqual(command.requests.map { $0.context["path"] }, ["/home/alice/api", "/home/alice/web"])
    }

    func testASessionSwitchClearsTheOtherSessionsOutput() async {
        command = ScriptedSourceRunner([.success(.output(.text("api files"))), .failure(.exited(status: 2, stderr: "no"))])
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.start()
        board.update([contextEntry()])
        await waitUntil { board.state("here").output == .text("api files") }
        board.setContext(["path": "/home/alice/web"])
        await waitUntil { board.state("here").error != nil }
        XCTAssertNil(board.state("here").output)
    }

    func testAnInlineWidgetAsksAgainWhenItsResolvedContextChanges() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.start()
        board.update([contextEntry(inline: true)])
        guard case .waiting = board.approvalState("here") else { return XCTFail("\(board.approvalState("here"))") }
        board.approve("here", hash: shown(board, "here"))
        XCTAssertEqual(board.approvalState("here").canRun, true)
        board.setContext(["path": "/home/alice/web"])
        guard case .waiting = board.approvalState("here") else { return XCTFail("\(board.approvalState("here"))") }
        board.setContext(["path": "/home/alice/api"])
        XCTAssertEqual(board.approvalState("here").canRun, true)
    }

    func testASessionSwitchRestartsAStreamWithTheNewContext() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.start()
        board.update([entry("log", run: "tail", inline: false, mode: .stream, args: ["{{context.path}}"])])
        await waitUntil { self.launcher.processes.count == 1 }
        launcher.write("api line\n")
        await waitUntil { board.state("log").lines == ["api line"] }
        board.setContext(["path": "/home/alice/web"])
        XCTAssertTrue(launcher.processes[0].isTerminated)
        await waitUntil { self.launcher.processes.count == 2 }
        XCTAssertTrue(board.state("log").lines.isEmpty)
        XCTAssertTrue(launcher.invocations[1].arguments.contains("/home/alice/web"))
    }

    func testASessionSwitchKeepsTheSparklineHistory() async {
        command = ScriptedSourceRunner([.success(.output(.number(42))), .success(.output(.number(7)))])
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.start()
        board.update([entry("load", inline: false, view: "sparkline", parse: .number, args: ["{{context.path}}"])])
        await waitUntil { board.history("load").count == 1 }
        board.setContext(["path": "/home/alice/web"])
        await waitUntil { board.history("load").count == 2 }
        XCTAssertEqual(board.history("load").map(\.value), [42, 7])
    }

    private func shown(_ board: WidgetSourceController, _ id: String) -> String {
        SourceWidgetCard.shownHash(board.approvalState(id))
    }

    private var approvalsFile: URL { folder.appendingPathComponent("approvals.json") }

    func testAllowForTheOldContextsHashAllowsNothingAfterASwitch() async {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.start()
        board.update([contextEntry(inline: true)])
        let apiHash = shown(board, "here")
        board.setContext(["path": "/home/alice/web"])
        board.approve("here", hash: apiHash)
        guard case let .waiting(webHash) = board.approvalState("here") else { return XCTFail("\(board.approvalState("here"))") }
        XCTAssertNotEqual(webHash, apiHash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: approvalsFile.path))
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(command.calls, 0)

        board.approve("here", hash: webHash)
        XCTAssertEqual(board.approvalState("here"), .allowed)
        await waitUntil { self.command.calls == 1 }
        XCTAssertEqual(command.requests[0].context["path"], "/home/alice/web")
    }

    func testDenyForTheOldContextsHashDeniesNothingAfterASwitch() {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.start()
        board.update([contextEntry(inline: true)])
        let apiHash = shown(board, "here")
        board.setContext(["path": "/home/alice/web"])
        board.deny("here", hash: apiHash)
        guard case .waiting = board.approvalState("here") else { return XCTFail("\(board.approvalState("here"))") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: approvalsFile.path))
    }

    func testASessionSwitchRedrawsAnAllowedWidgetThatHasNotRunYet() {
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"])
        board.update([contextEntry(inline: true)])
        board.approve("here", hash: shown(board, "here"))
        XCTAssertEqual(board.approvalState("here"), .allowed)
        var changes = 0
        let watching = board.objectWillChange.sink { changes += 1 }
        board.setContext(["path": "/home/alice/web"])
        watching.cancel()
        XCTAssertGreaterThan(changes, 0)
        guard case .waiting = board.approvalState("here") else { return XCTFail("\(board.approvalState("here"))") }
    }

    func testALateAnswerForTheOldContextNeverShows() async {
        let stubborn = StubbornSourceRunner()
        defer { stubborn.releaseAll() }
        let board = makeController(surface: "context-sidebar", context: ["path": "/home/alice/api"], runner: stubborn)
        board.start()
        board.update([contextEntry()])
        await waitUntil { stubborn.calls == 1 }
        board.setContext(["path": "/home/alice/web"])
        await waitUntil { stubborn.calls == 2 }
        stubborn.release(1)
        await waitUntil { board.state("here").output == .text("/home/alice/web") }
        stubborn.release(0)
        await waitUntil { stubborn.answered == 2 }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(board.state("here").output, .text("/home/alice/web"))
    }
}

private final class StubbornSourceRunner: SourceRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var held: [CheckedContinuation<Void, Never>?] = []
    private var received: [SourceRunRequest] = []
    private var done = 0

    func fetch(_ request: SourceRunRequest) async throws -> SourceRunResult {
        await withCheckedContinuation { continuation in
            lock.withLock {
                received.append(request)
                held.append(continuation)
            }
        }
        lock.withLock { done += 1 }
        return .output(.text(request.context["path"] ?? ""))
    }

    var calls: Int { lock.withLock { received.count } }
    var answered: Int { lock.withLock { done } }

    func release(_ index: Int) {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { held[index] = nil }
            return held[index]
        }
        continuation?.resume()
    }

    func releaseAll() {
        for index in 0..<lock.withLock({ held.count }) { release(index) }
    }
}
