import XCTest
@testable import DevmachineCore

final class SourceScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func job(
        _ id: String, _ every: WidgetEvery, runnable: Bool = true, visible: Bool = true, signature: String = "a"
    ) -> SourceJob {
        SourceJob(instanceID: id, every: every, isRunnable: runnable, isVisible: visible, signature: signature)
    }

    private func sourceJob(_ source: WidgetSource) -> SourceJob {
        let resolved = ResolvedSource(
            source: source, view: WidgetView(kind: "text"), every: source.every, needsApproval: true, package: nil,
            packagePath: nil)
        return SourceJob(instanceID: "w", source: resolved, isRunnable: true, isVisible: true, signature: "a")
    }

    private func command(every: WidgetEvery) -> WidgetSource {
        .command(CommandSource(
            run: "df", script: nil, args: [], shell: false, target: .local, every: every, timeout: 30, mode: .poll,
            keep: 200, parse: .text))
    }

    func testAPollIsDueAtOnceThenWaitsItsInterval() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(60))])
        XCTAssertEqual(schedule.due(now: start), ["disk"])
        schedule.begin("disk", at: start)
        schedule.finish("disk")
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(59)), [])
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(60)), ["disk"])
    }

    func testACancelledRunIsDueAgainAtOnce() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(60))])
        schedule.begin("disk", at: start)
        schedule.cancel("disk")
        XCTAssertFalse(schedule.isInFlight("disk"))
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(1)), ["disk"])
    }

    func testManualAndStreamsAreNeverDue() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("today", .manual), job("log", .continuous)])
        XCTAssertEqual(schedule.due(now: start), [])
        XCTAssertTrue(schedule.canRunNow("today"))
        XCTAssertEqual(schedule.streams, ["log"])
    }

    func testARunningStreamStaysAStream() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("log", .continuous)])
        schedule.begin("log", at: start)
        XCTAssertEqual(schedule.streams, ["log"])
    }

    func testOneRunInFlightPerWidget() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(5))])
        schedule.begin("disk", at: start)
        XCTAssertTrue(schedule.isInFlight("disk"))
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(600)), [])
        XCTAssertFalse(schedule.canRunNow("disk"))
        schedule.finish("disk")
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(600)), ["disk"])
    }

    func testHiddenOrNotAllowedWidgetsDoNotRun() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([
            job("hidden", .interval(5), visible: false), job("waiting", .interval(5), runnable: false),
            job("stream", .continuous, visible: false), job("paused", .manual, runnable: false),
        ])
        XCTAssertEqual(schedule.due(now: start), [])
        XCTAssertEqual(schedule.streams, [])
        XCTAssertFalse(schedule.canRunNow("paused"))
        XCTAssertFalse(schedule.canRunNow("unknown"))
    }

    func testASameSignatureKeepsItsLastRunAndANewOneStartsOver() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(60))])
        schedule.begin("disk", at: start)
        schedule.finish("disk")
        schedule.replaceJobs([job("disk", .interval(60))])
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(1)), [])
        schedule.replaceJobs([job("disk", .interval(60), signature: "b")])
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(1)), ["disk"])
    }

    func testDueIDsComeInAStableOrder() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("b", .interval(5)), job("a", .interval(5))])
        XCTAssertEqual(schedule.due(now: start), ["a", "b"])
    }

    func testAWidgetWaitingForApprovalIsPausedNotDue() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(5)), job("today", .manual), job("log", .continuous)])
        for id in ["disk", "today", "log"] {
            schedule.begin(id, at: start)
            schedule.finish(id)
        }
        schedule.pause("disk", for: .waiting(hash: "h1"))
        schedule.pause("today", for: .denied(hash: "h2"))
        schedule.pause("log", for: .waiting(hash: "h3"))
        XCTAssertTrue(schedule.isPaused("disk"))
        XCTAssertFalse(schedule.isInFlight("disk"))
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(600)), [])
        XCTAssertFalse(schedule.canRunNow("today"))
        XCTAssertEqual(schedule.streams, [])
    }

    func testAnAllowedStateDoesNotPause() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(5))])
        schedule.pause("disk", for: .allowed)
        schedule.pause("disk", for: .notNeeded)
        XCTAssertFalse(schedule.isPaused("disk"))
        XCTAssertEqual(schedule.due(now: start), ["disk"])
    }

    func testNewApprovalsResumeEveryPausedWidget() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(5)), job("log", .continuous)])
        schedule.pause("disk", for: .waiting(hash: "h1"))
        schedule.pause("log", for: .denied(hash: "h2"))
        schedule.resumeAll()
        XCTAssertEqual(schedule.due(now: start), ["disk"])
        XCTAssertEqual(schedule.streams, ["log"])
    }

    func testANewSignatureOrARemovedWidgetEndsThePause() {
        var schedule = SourceSchedule()
        schedule.replaceJobs([job("disk", .interval(5)), job("cpu", .interval(5))])
        schedule.pause("disk", for: .waiting(hash: "h1"))
        schedule.pause("cpu", for: .waiting(hash: "h2"))
        schedule.replaceJobs([job("disk", .interval(5)), job("cpu", .interval(5), signature: "b")])
        XCTAssertEqual(schedule.due(now: start), ["cpu"])
        schedule.replaceJobs([job("cpu", .interval(5), signature: "b")])
        schedule.replaceJobs([job("disk", .interval(5)), job("cpu", .interval(5), signature: "b")])
        XCTAssertEqual(schedule.due(now: start), ["cpu", "disk"])
    }

    func testPausingAnUnknownWidgetDoesNothing() {
        var schedule = SourceSchedule()
        schedule.pause("ghost", for: .waiting(hash: "h"))
        schedule.replaceJobs([job("ghost", .interval(5))])
        XCTAssertEqual(schedule.due(now: start), ["ghost"])
    }

    func testAJobFromASourceIsRaisedToItsKindsMinimum() {
        let cases: [(WidgetSource, TimeInterval)] = [
            (command(every: .interval(1)), 5),
            (.url(URLSource(url: "https://example.com", every: .interval(1), timeout: 30, parse: .status)), 5),
            (.session(SessionSource(target: .local, session: "main", every: .interval(1))), 2),
            (.prompt(PromptSource(harness: .claude, prompt: "hi", target: .local, every: .interval(60), timeout: 300)), 900),
        ]
        for (source, floor) in cases {
            XCTAssertEqual(sourceJob(source).every, .interval(floor), source.kind)
        }
    }

    func testAJobFromASourceKeepsALongerIntervalManualAndStreams() {
        let manual = WidgetSource.prompt(PromptSource(harness: .codex, prompt: "hi", target: .local, every: .manual, timeout: 300))
        let stream = WidgetSource.session(SessionSource(target: .local, session: "main", every: .continuous))
        XCTAssertEqual(sourceJob(command(every: .interval(120))).every, .interval(120))
        XCTAssertEqual(sourceJob(manual).every, .manual)
        XCTAssertEqual(sourceJob(stream).every, .continuous)
    }

    func testAFreshWidgetStateShowsNothingYet() {
        let state = SourceWidgetState()
        XCTAssertNil(state.output)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.lastSuccess)
        XCTAssertEqual(state.lines, [])
        XCTAssertFalse(state.ended)
    }
}
