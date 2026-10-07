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

    func testANewReadOfTheSameSessionProbesAgainAndKeepsTheLastAnswerMeanwhile() async {
        let script = Script([.success("main\n\n"), .success("feature\n\n")])
        let store = ContextGitStatusStore(run: { _, _ in try script.next() })
        let target = CommandTarget.remote(alias: "alice-dev-devmachine", session: "api")
        store.refresh(target, cwd: "/home/alice/api", revision: "10:00:00")
        await waitUntil { store.status?.branch == "main" }
        store.refresh(target, cwd: "/home/alice/api", revision: "10:00:00")
        XCTAssertEqual(script.count, 1)
        store.refresh(target, cwd: "/home/alice/api", revision: "10:00:05")
        XCTAssertEqual(store.status?.branch, "main")
        XCTAssertFalse(store.isPending)
        await waitUntil { store.status?.branch == "feature" }
        XCTAssertEqual(script.count, 2)
    }

    func testAFailedProbeIsRetriedOnceOnTheNextReadThenWaits() async {
        let script = Script([.failure(Boom())])
        let store = ContextGitStatusStore(run: { _, _ in try script.next() })
        let target = CommandTarget.remote(alias: "alice-dev-devmachine", session: "api")
        store.refresh(target, cwd: nil, revision: "1")
        await waitUntil { store.status != nil }
        store.refresh(target, cwd: nil, revision: "2")
        await waitUntil { script.count == 2 }
        try? await Task.sleep(for: .milliseconds(30))
        store.refresh(target, cwd: nil, revision: "3")
        store.refresh(target, cwd: nil, revision: "4")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(script.count, 2)
        store.appeared()
        await waitUntil { script.count == 3 }
    }

    func testAFailedProbeAfterAGoodOneKeepsTheGoodAnswer() async {
        let script = Script([.success("main\ngit@example.com:acme/api.git\n"), .failure(Boom())])
        let store = ContextGitStatusStore(run: { _, _ in try script.next() })
        let target = CommandTarget.remote(alias: "alice-dev-devmachine", session: "api")
        store.refresh(target, cwd: nil, revision: "1")
        await waitUntil { store.status != nil }
        store.refresh(target, cwd: nil, revision: "2")
        await waitUntil { script.count == 2 }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(store.status, ContextGitStatus(branch: "main", repo: "acme/api"))
    }

    func testTheTabComingBackProbesAgain() async {
        let script = Script([.success("main\n\n"), .success("feature\n\n")])
        let store = ContextGitStatusStore(run: { _, _ in try script.next() })
        store.appeared()
        XCTAssertEqual(script.count, 0)
        store.refresh(.local(session: "notes", path: "/Users/alice/notes"), cwd: nil)
        XCTAssertTrue(store.isPending)
        await waitUntil { store.status?.branch == "main" }
        XCTAssertFalse(store.isPending)
        store.appeared()
        await waitUntil { store.status?.branch == "feature" }
    }
}
