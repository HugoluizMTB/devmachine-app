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
        isDemo: Bool = false, surface: String = "home", context: [String: String] = [:]
    ) -> WidgetSourceController {
        let environment = SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: [:]) },
            localEnvironment: [:], home: "/Users/alice", isExecutable: { _ in true })
        let runners = SourceRunners(
            command: command, url: command, prompt: command, session: command, launcher: launcher, environment: environment)
        let made = WidgetSourceController(
            runners: runners, approvalsFile: WidgetApprovalsFile(fileURL: folder.appendingPathComponent("approvals.json")),
            historyStore: SparklineHistoryStore(directory: folder.appendingPathComponent("history")), surface: surface,
            context: context, isDemo: isDemo, now: { [unowned self] in self.clock })
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
        controller.approve("disk")
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
        controller.deny("disk")
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
        controller.approve("disk")
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
        controller.approve("disk")
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
        controller.approve("disk")
        await waitUntil { self.command.calls == 1 }
        controller.deny("disk")
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
        controller.approve("disk")
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
        controller.approve("log")
        await waitUntil { self.launcher.processes.count == 1 }
        controller.deny("log")
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
}
