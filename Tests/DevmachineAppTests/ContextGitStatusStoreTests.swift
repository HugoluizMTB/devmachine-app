import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class ContextGitStatusStoreTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [(String, String)] = []
        func record(_ target: CommandTarget, _ body: String) { lock.withLock { made.append((target.key, body)) } }
        var count: Int { lock.withLock { made.count } }
        var keys: [String] { lock.withLock { made.map(\.0) } }
        var bodies: [String] { lock.withLock { made.map(\.1) } }
    }

    func testReadsBranchAndRepoForTheTarget() async {
        let calls = Calls()
        let store = ContextGitStatusStore(run: { target, body in
            calls.record(target, body)
            return "main\ngit@github.com:acme/api.git\n"
        })
        store.refresh(.remote(alias: "alice-dev-devmachine", session: "api"), cwd: "/home/alice/api")
        await waitUntil { store.status != nil }
        XCTAssertEqual(store.status, ContextGitStatus(branch: "main", repo: "acme/api"))
        XCTAssertEqual(calls.keys, ["alice-dev-devmachine/api"])
        XCTAssertEqual(calls.bodies, [ContextGitProbe.body])
    }

    func testTheSameTargetAndFolderIsReadOnce() async {
        let calls = Calls()
        let store = ContextGitStatusStore(run: { target, body in
            calls.record(target, body)
            return "main\n\n"
        })
        let target = CommandTarget.remote(alias: "alice-dev-devmachine", session: "api")
        store.refresh(target, cwd: "/home/alice/api")
        await waitUntil { store.status != nil }
        store.refresh(target, cwd: "/home/alice/api")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls.count, 1)
        store.refresh(target, cwd: "/home/alice/web")
        await waitUntil { calls.count == 2 }
    }

    func testNoTargetClearsAndALateAnswerIsDropped() async {
        let store = ContextGitStatusStore(run: { _, _ in
            Thread.sleep(forTimeInterval: 0.05)
            return "main\nhttps://example.com/acme/api.git\n"
        })
        store.refresh(.remote(alias: "alice-dev-devmachine", session: "api"), cwd: nil)
        store.refresh(nil, cwd: nil)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(store.status)
    }

    func testAFailedReadLeavesEmptyKeys() async {
        struct Boom: Error {}
        let store = ContextGitStatusStore(run: { _, _ in throw Boom() })
        store.refresh(.local(session: "notes", path: "/Users/alice/notes"), cwd: nil)
        await waitUntil { store.status != nil }
        XCTAssertEqual(store.status, ContextGitStatus(branch: "", repo: ""))
    }

    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [Result<String, Error>]
        private var made = 0
        init(_ answers: [Result<String, Error>]) { self.answers = answers }
        func next() throws -> String {
            try lock.withLock {
                made += 1
                return answers.count > 1 ? answers.removeFirst() : answers[0]
            }.get()
        }
        var count: Int { lock.withLock { made } }
    }

    private struct Boom: Error {}

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    func testTheThrottleLetsANewReadProbeOnlyThirtySecondsAfterTheLastProbe() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(GitProbeThrottle.allows(.newRead, lastProbe: nil, now: start))
        XCTAssertFalse(GitProbeThrottle.allows(.newRead, lastProbe: start, now: start.addingTimeInterval(5)))
        XCTAssertFalse(GitProbeThrottle.allows(.newRead, lastProbe: start, now: start.addingTimeInterval(29.9)))
        XCTAssertTrue(GitProbeThrottle.allows(.newRead, lastProbe: start, now: start.addingTimeInterval(30)))
    }

    func testANewSessionOrFolderOrTheTabProbesAtOnce() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(GitProbeThrottle.allows(.newTarget, lastProbe: start, now: start.addingTimeInterval(1)))
        XCTAssertTrue(GitProbeThrottle.allows(.appeared, lastProbe: start, now: start.addingTimeInterval(1)))
    }

    func testANewReadProbesAgainOnlyAfterThirtySecondsAndKeepsTheLastAnswerMeanwhile() async {
        let script = Script([.success("main\n\n"), .success("feature\n\n")])
        let clock = Clock()
        let store = ContextGitStatusStore(run: { _, _ in try script.next() }, now: { clock.now })
        let target = CommandTarget.remote(alias: "alice-dev-devmachine", session: "api")
        store.refresh(target, cwd: "/home/alice/api", revision: "10:00:00")
        await waitUntil { store.status?.branch == "main" }
        clock.advance(5)
        store.refresh(target, cwd: "/home/alice/api", revision: "10:00:05")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(script.count, 1)
        clock.advance(25)
        store.refresh(target, cwd: "/home/alice/api", revision: "10:00:30")
        XCTAssertEqual(store.status?.branch, "main")
        XCTAssertFalse(store.isPending)
        await waitUntil { store.status?.branch == "feature" }
        XCTAssertEqual(script.count, 2)
    }

    func testAFailedProbeIsRetriedOnTheNextReadAfterThirtySecondsNotSooner() async {
        let script = Script([.failure(Boom()), .success("main\n\n")])
        let clock = Clock()
        let store = ContextGitStatusStore(run: { _, _ in try script.next() }, now: { clock.now })
        let target = CommandTarget.remote(alias: "alice-dev-devmachine", session: "api")
        store.refresh(target, cwd: nil, revision: "1")
        await waitUntil { store.status != nil }
        XCTAssertEqual(store.status, ContextGitStatus(branch: "", repo: ""))
        clock.advance(10)
        store.refresh(target, cwd: nil, revision: "2")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(script.count, 1)
        clock.advance(20)
        store.refresh(target, cwd: nil, revision: "3")
        await waitUntil { store.status?.branch == "main" }
        XCTAssertEqual(script.count, 2)
    }

    func testAFailedProbeAfterAGoodOneKeepsTheGoodAnswer() async {
        let script = Script([.success("main\ngit@example.com:acme/api.git\n"), .failure(Boom())])
        let clock = Clock()
        let store = ContextGitStatusStore(run: { _, _ in try script.next() }, now: { clock.now })
        let target = CommandTarget.remote(alias: "alice-dev-devmachine", session: "api")
        store.refresh(target, cwd: nil, revision: "1")
        await waitUntil { store.status != nil }
        clock.advance(30)
        store.refresh(target, cwd: nil, revision: "2")
        await waitUntil { script.count == 2 }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(store.status, ContextGitStatus(branch: "main", repo: "acme/api"))
    }

    func testTheTabComingBackProbesAtOnce() async {
        let script = Script([.success("main\n\n"), .success("feature\n\n")])
        let clock = Clock()
        let store = ContextGitStatusStore(run: { _, _ in try script.next() }, now: { clock.now })
        store.appeared()
        XCTAssertEqual(script.count, 0)
        store.refresh(.local(session: "notes", path: "/Users/alice/notes"), cwd: nil)
        XCTAssertTrue(store.isPending)
        await waitUntil { store.status?.branch == "main" }
        XCTAssertFalse(store.isPending)
        clock.advance(1)
        store.appeared()
        await waitUntil { store.status?.branch == "feature" }
    }
}
