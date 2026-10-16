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

    func testResetStartsANewThread() async {
        let list = "[\(ChatFixtures.record("a1", kind: "ask", session: "claude — api"))]"
        let runner = FakeChatRunner(outputs: ["chat list": ChatCommandOutput(stdout: list, stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        await store.refresh()
        let asks = AskStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let key = AskSessionKey(place: .workspace("main"), session: "claude — api")
        XCTAssertEqual(asks.threadID(for: key, in: store), "a1")
        asks.reset(key)
        XCTAssertNil(asks.threadID(for: key, in: store))
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

    func testContinueInChatsMakesItAChatAndOpensIt() async {
        let list = "[\(ChatFixtures.record("a1", workspace: "main", kind: "ask", session: "claude — api"))]"
        let continued = ChatFixtures.record("a1", workspace: "main", kind: "chat", session: "claude — api")
        let runner = FakeChatRunner(outputs: [
            "chat list": ChatCommandOutput(stdout: list, stderr: "", exitCode: 0),
            "chat continue": ChatCommandOutput(stdout: continued, stderr: "", exitCode: 0),
        ])
        let store = ChatStore(runner: runner)
        await store.refresh()
        let model = AppModel(services: fixtureServices())
        let asks = AskStore()
        let key = AskSessionKey(place: .workspace("main"), session: "claude — api")
        await asks.continueInChats(key, store: store, model: model)
        XCTAssertTrue(runner.arguments.contains(["chat", "continue", "a1", "--json"]))
        XCTAssertEqual(store.visibleChats.map(\.id), ["a1"])
        XCTAssertEqual(model.appMode, .chats)
        XCTAssertEqual(store.selectedID, "a1")
        XCTAssertNil(asks.threadID(for: key, in: store))
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
