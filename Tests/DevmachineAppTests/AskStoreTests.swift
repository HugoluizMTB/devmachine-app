import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class AskStoreTests: XCTestCase {
    private let key = AskSessionKey(place: .workspace("acme"), session: "claude — api")

    func testTheFirstAskStartsTheSessionsThreadAndAFollowUpContinuesIt() async {
        let runner = FakeChatRunner(streams: [
            .init(lines: [ChatFixtures.started("a1", kind: "ask", session: "claude — api"), ChatFixtures.text("It"),
                          ChatFixtures.done("a1", kind: "ask", session: "claude — api")]),
            .init(lines: [ChatFixtures.started("a1", kind: "ask", session: "claude — api"),
                          ChatFixtures.done("a1", kind: "ask", session: "claude — api")]),
        ])
        let store = ChatStore(runner: runner)
        let asks = AskStore()
        asks.ask("why?", key: key, mode: .supported(.claude), folder: nil, store: store)
        await waitForChat { asks.threadID(for: self.key, in: store) == "a1" && !store.isAnswering("a1") }
        XCTAssertEqual(
            runner.arguments[0],
            ["chat", "ask", "--workspace", "acme", "--session", "claude — api", "--harness", "claude", "--", "why?"])
        XCTAssertTrue(store.visibleChats.isEmpty)
        asks.ask("and?", key: key, mode: .supported(.claude), folder: nil, store: store)
        await waitForChat { runner.arguments.count == 2 }
        XCTAssertEqual(runner.arguments[1].suffix(4), ["--chat", "a1", "--", "and?"])
    }

    func testEachSessionHasItsOwnThreadFromTheList() async {
        let list = "[\(ChatFixtures.record("a1", kind: "ask", session: "claude — api")),"
            + "\(ChatFixtures.record("a2", kind: "ask", session: "codex"))]"
        let runner = FakeChatRunner(outputs: ["chat list": ChatCommandOutput(stdout: list, stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        await store.refresh()
        let asks = AskStore()
        XCTAssertEqual(asks.threadID(for: AskSessionKey(place: .workspace("main"), session: "claude — api"), in: store), "a1")
        XCTAssertEqual(asks.threadID(for: AskSessionKey(place: .workspace("main"), session: "codex"), in: store), "a2")
        XCTAssertNil(asks.threadID(for: AskSessionKey(place: .local, session: "codex"), in: store))
    }

    private func storeWithAsk(deleteExit: Int32 = 0) async -> (ChatStore, FakeChatRunner) {
        let list = "[\(ChatFixtures.record("a1", kind: "ask", session: "claude — api"))]"
        let runner = FakeChatRunner(outputs: [
            "chat list": ChatCommandOutput(stdout: list, stderr: "", exitCode: 0),
            "chat delete": ChatCommandOutput(
                stdout: "", stderr: deleteExit == 0 ? "" : "error: cannot remove the chat", exitCode: deleteExit),
        ])
        let store = ChatStore(runner: runner)
        await store.refresh()
        return (store, runner)
    }

    func testEachSessionKeepsItsOwnDraftAndClearDropsIt() async {
        let (store, _) = await storeWithAsk()
        let asks = AskStore()
        let other = AskSessionKey(place: .workspace("acme"), session: "codex")
        asks.drafts[key] = "why?"
        asks.drafts[other] = "what changed?"
        await asks.clear(key, store: store)
        XCTAssertNil(asks.drafts[key])
        XCTAssertEqual(asks.drafts[other], "what changed?")
    }

    func testClearDeletesTheThreadSoARestartDoesNotBringItBack() async {
        let (store, runner) = await storeWithAsk()
        let key = AskSessionKey(place: .workspace("main"), session: "claude — api")
        let asks = AskStore()
        XCTAssertEqual(asks.threadID(for: key, in: store), "a1")
        await asks.clear(key, store: store)
        XCTAssertTrue(runner.arguments.contains(["chat", "delete", "a1"]))
        XCTAssertNil(asks.threadID(for: key, in: store))
        XCTAssertNil(asks.clearFailures[key])
        XCTAssertNil(AskStore().threadID(for: key, in: store))
    }

    func testAFailedDeleteKeepsTheThreadAndSaysWhy() async {
        let (store, _) = await storeWithAsk(deleteExit: 1)
        let key = AskSessionKey(place: .workspace("main"), session: "claude — api")
        let asks = AskStore()
        await asks.clear(key, store: store)
        XCTAssertEqual(asks.threadID(for: key, in: store), "a1")
        XCTAssertEqual(asks.clearFailures[key], "error: cannot remove the chat")
    }

    func testClearWaitsWhileTheAnswerIsComing() async {
        let runner = FakeChatRunner(streams: [.init(lines: [ChatFixtures.started("a1", kind: "ask")], waitsForCancel: true)])
        let store = ChatStore(runner: runner)
        let asks = AskStore()
        asks.ask("why?", key: key, mode: .supported(.claude), folder: nil, store: store)
        await waitForChat { asks.threadID(for: self.key, in: store) == "a1" }
        let cleared = await asks.clear(key, store: store)
        XCTAssertFalse(cleared)
        XCTAssertTrue(store.isAnswering("a1"))
        XCTAssertFalse(runner.arguments.contains { $0.prefix(2) == ["chat", "delete"] })
        store.stop("a1")
    }

    func testAPendingThreadIsClearedWithoutAskingTheCLI() async {
        let runner = FakeChatRunner(streams: [.init(lines: ["ssh: connection refused"], status: 255)])
        let store = ChatStore(runner: runner)
        let asks = AskStore()
        let pending = asks.ask("why?", key: key, mode: .supported(.claude), folder: nil, store: store)!
        await waitForChat { !store.isAnswering(pending) }
        await asks.clear(key, store: store)
        XCTAssertNil(asks.threadID(for: key, in: store))
        XCTAssertFalse(runner.arguments.contains { $0.prefix(2) == ["chat", "delete"] })
    }

    func testAnUnsupportedHarnessSendsNothing() {
        let runner = FakeChatRunner()
        let asks = AskStore()
        XCTAssertNil(asks.ask("why?", key: key, mode: .unsupported(.pi), folder: nil, store: ChatStore(runner: runner)))
        XCTAssertTrue(runner.arguments.isEmpty)
    }

    func testASessionOnThisMacPassesItsFolder() async {
        let runner = FakeChatRunner(streams: [.init(lines: [])])
        let asks = AskStore()
        asks.ask(
            "why?", key: AskSessionKey(place: .local, session: "api"), mode: .supported(.codex),
            folder: "/Users/alice/dev/api", store: ChatStore(runner: runner))
        await waitForChat { !runner.arguments.isEmpty }
        XCTAssertEqual(
            runner.arguments[0],
            ["chat", "ask", "--local", "--session", "api", "--folder", "/Users/alice/dev/api", "--harness", "codex",
             "--", "why?"])
    }

    func testTheAnswerShowsAsComingRightAfterSend() {
        let runner = FakeChatRunner(streams: [.init(lines: [], waitsForCancel: true)])
        let store = ChatStore(runner: runner)
        let sent = AskStore().ask("why?", key: key, mode: .supported(.claude), folder: nil, store: store)
        XCTAssertNotNil(sent)
        XCTAssertTrue(store.isAnswering(sent!))
        store.stop(sent!)
    }
}
