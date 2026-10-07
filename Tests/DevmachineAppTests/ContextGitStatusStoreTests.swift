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
}
