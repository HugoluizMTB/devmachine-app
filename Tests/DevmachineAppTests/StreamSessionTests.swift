import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class StreamSessionTests: XCTestCase {
    private var launcher: AppFakeLauncher!

    override func setUp() async throws {
        launcher = AppFakeLauncher()
    }

    override func tearDown() async throws {
        launcher.releaseAll()
    }

    private let tail = ProcessInvocation(executable: "/usr/bin/tail", arguments: ["-f", "/tmp/x"])

    func testLinesArriveInBatchesAndKeepTheLastN() {
        let session = StreamSession(launcher: launcher, keep: 2)
        var seen: [[String]] = []
        session.onLines = { seen.append($0) }
        session.start(tail, remote: false)
        launcher.write("one\ntwo\nthr")
        launcher.write("ee\n")
        session.flushNow()
        XCTAssertEqual(session.lines, ["two", "three"])
        XCTAssertEqual(seen, [["two", "three"]])
        session.stop()
    }

    func testTheBatchTimerDeliversLinesWithoutAFlushCall() async {
        let session = StreamSession(launcher: launcher, keep: 10)
        var seen: [[String]] = []
        session.onLines = { seen.append($0) }
        session.start(tail, remote: false)
        launcher.write("a\n")
        await waitUntil { seen == [["a"]] }
        session.stop()
    }

    func testKeepFallsBackToTheDefaultAndStopsAtTheMaximum() {
        XCTAssertEqual(StreamSession.lineLimit(0), 200)
        XCTAssertEqual(StreamSession.lineLimit(-3), 200)
        XCTAssertEqual(StreamSession.lineLimit(50), 50)
        XCTAssertEqual(StreamSession.lineLimit(5000), 2000)
    }

    func testStopSendsSIGTERMAndIgnoresTheExit() async {
        let session = StreamSession(launcher: launcher, keep: 10)
        var ended = false
        session.onEnd = { _ in ended = true }
        session.start(tail, remote: true)
        session.stop()
        XCTAssertTrue(launcher.processes[0].isTerminated)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(ended)
    }

    func testAStreamThatEndsSaysWhy() async {
        let session = StreamSession(launcher: launcher, keep: 10)
        var reason: SourceError??
        session.onEnd = { reason = .some($0) }
        session.start(ProcessInvocation(executable: "/opt/homebrew/bin/devmachine", arguments: []), remote: true)
        launcher.processes[0].finish(ProcessExit(status: 255, stderr: "error: main cannot be reached\n", stoppedByCaller: false))
        await waitUntil { reason != nil }
        XCTAssertEqual(reason, .some(.neverRan("main cannot be reached")))
    }

    func testAStreamThatEndsCleanlyKeepsItsLastPartialLine() async {
        let session = StreamSession(launcher: launcher, keep: 10)
        var reason: SourceError??
        session.onEnd = { reason = .some($0) }
        session.start(tail, remote: false)
        launcher.write("done\nhalf")
        launcher.processes[0].finish(ProcessExit(status: 0, stderr: "", stoppedByCaller: false))
        await waitUntil { reason != nil }
        XCTAssertEqual(reason, .some(nil))
        XCTAssertEqual(session.lines, ["done", "half"])
    }

    func testALaunchThatFailsEndsAtOnce() {
        launcher.failNextLaunches(with: CocoaError(.fileNoSuchFile))
        let session = StreamSession(launcher: launcher, keep: 10)
        var reason: SourceError?
        session.onEnd = { reason = $0 }
        session.start(tail, remote: false)
        guard case .cannotStart? = reason else { return XCTFail("\(String(describing: reason))") }
    }
}
