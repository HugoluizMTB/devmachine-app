import XCTest
import DevmachineCore
@testable import DevmachineApp

final class FakeSessionChannel: ChatSessionChannel, @unchecked Sendable {
    let arguments: [String]
    private let lock = NSLock()
    private var written: [String] = []
    private var isClosed = false
    private let line: @Sendable (String) -> Void
    private let exited: @Sendable (Int32) -> Void

    init(arguments: [String], line: @escaping @Sendable (String) -> Void, exited: @escaping @Sendable (Int32) -> Void) {
        self.arguments = arguments
        self.line = line
        self.exited = exited
    }

    var writes: [String] { lock.withLock { written } }
    var closed: Bool { lock.withLock { isClosed } }

    func write(_ line: String) { lock.withLock { written.append(line) } }
    func close() { lock.withLock { isClosed = true } }

    func emit(_ lines: String...) { lines.forEach(line) }
    func exit(_ status: Int32) { exited(status) }
}

final class FakeSessionRunner: ChatCommandRunning, @unchecked Sendable {
    let base = FakeChatRunner(streams: [
        .init(lines: [ChatFixtures.started("c1"), ChatFixtures.done("c1")]),
    ])
    private let lock = NSLock()
    private var opened: [FakeSessionChannel] = []

    var channels: [FakeSessionChannel] { lock.withLock { opened } }

    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        try await base.stream(arguments, line: line)
    }

    func run(_ arguments: [String]) async throws -> ChatCommandOutput {
        try await base.run(arguments)
    }

    func openSession(
        _ arguments: [String], line: @escaping @Sendable (String) -> Void,
        exited: @escaping @Sendable (Int32) -> Void
    ) throws -> any ChatSessionChannel {
        let channel = FakeSessionChannel(arguments: arguments, line: line, exited: exited)
        lock.withLock { opened.append(channel) }
        return channel
    }
}

@MainActor
final class ChatSessionStoreTests: XCTestCase {
    private let spec = ChatSessionSpec(harness: .claude, place: .local, mcp: false)

    func testAWarmSessionTakesTheFirstMessageAndStaysForTheNext() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        store.prewarm(spec)
        store.prewarm(spec)
        XCTAssertEqual(runner.channels.map(\.arguments), [["chat", "session", "--local", "--harness", "claude"]])
        let warm = runner.channels[0]
        warm.emit(#"{"type":"ready","chat":null}"#)
        let key = store.send("hi", harness: .claude, place: .local)!
        XCTAssertEqual(warm.writes, [ChatSessionInput.send("hi")])
        warm.emit(ChatFixtures.started("c1"), ChatFixtures.text("Hello"), ChatFixtures.done("c1"))
        await waitForChat { store.current(key) == "c1" && !store.isAnswering("c1") }
        XCTAssertEqual(store.conversation("c1").messages.last?.text, "Hello")
        store.send("and?", toChat: "c1")
        XCTAssertEqual(warm.writes.last, ChatSessionInput.send("and?"))
        XCTAssertEqual(runner.channels.count, 1)
        XCTAssertTrue(runner.base.arguments.isEmpty)
    }

    func testAnotherHarnessOrWorkspaceReplacesTheWarmSession() {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        store.prewarm(spec)
        store.prewarm(ChatSessionSpec(harness: .codex, place: .workspace("main"), mcp: false))
        XCTAssertTrue(runner.channels[0].closed)
        XCTAssertEqual(runner.channels[1].arguments, ["chat", "session", "--workspace", "main", "--harness", "codex"])
        store.send("hi", harness: .claude, place: .local)
        XCTAssertEqual(runner.channels.count, 3)
        XCTAssertEqual(runner.channels[2].writes, [ChatSessionInput.send("hi")])
    }

    func testStopSendsCancel() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        let key = store.send("hi", harness: .claude, place: .local)!
        store.stop(key)
        XCTAssertEqual(runner.channels[0].writes.last, ChatSessionInput.cancel)
        XCTAssertFalse(store.isAnswering(key))
    }

    func testAStoppedTurnsLateEndDoesNotEndTheNextMessage() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        let key = store.send("hi", harness: .claude, place: .local)!
        let channel = runner.channels[0]
        channel.emit(ChatFixtures.started("c1"), ChatFixtures.text("par"))
        await waitForChat { store.current(key) == "c1" }
        store.stop("c1")
        store.send("again", toChat: "c1")
        XCTAssertEqual(channel.writes.suffix(2), [ChatSessionInput.cancel, ChatSessionInput.send("again")])
        channel.emit(
            ChatFixtures.text("tial"), #"{"type":"error","kind":"cancelled","message":"stopped"}"#,
            ChatFixtures.started("c1"), ChatFixtures.text("Fresh"), ChatFixtures.done("c1"))
        await waitForChat { !store.isAnswering("c1") }
        XCTAssertEqual(store.conversation("c1").messages.last?.text, "Fresh")
        XCTAssertNil(store.conversation("c1").failure)
    }

    func testAnOlderCLIGetsTheMessageThroughChatSend() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        let key = store.send("hi", harness: .claude, place: .local)!
        let channel = runner.channels[0]
        channel.emit(#"Error: unknown command "session" for "devmachine chat""#)
        channel.exit(1)
        await waitForChat { store.current(key) == "c1" && !store.isAnswering("c1") }
        XCTAssertEqual(runner.base.arguments.first?.prefix(2), ["chat", "send"])
        XCTAssertEqual(store.conversation("c1").messages.filter { $0.role == .user }.count, 1)
        XCTAssertNil(store.conversation("c1").failure)
        store.prewarm(spec)
        XCTAssertEqual(runner.channels.count, 1)
    }

    func testASessionThatDiesMidAnswerFailsTheTurn() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        let key = store.send("hi", harness: .claude, place: .local)!
        let channel = runner.channels[0]
        channel.emit(#"{"type":"ready","chat":null}"#, ChatFixtures.started("c1"), "ssh: connection reset")
        channel.exit(255)
        await waitForChat { store.current(key) == "c1" && !store.isAnswering("c1") }
        XCTAssertEqual(store.conversation("c1").failure?.message, "ssh: connection reset")
        store.send("again", toChat: "c1")
        XCTAssertEqual(runner.channels.count, 2)
        XCTAssertEqual(runner.channels[1].arguments, ["chat", "session", "--chat", "c1"])
    }

    func testAnMCPChangeRestartsTheChatsSession() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        let key = store.send("hi", harness: .claude, place: .local)!
        runner.channels[0].emit(ChatFixtures.started("c1"), ChatFixtures.done("c1"))
        await waitForChat { store.current(key) == "c1" && !store.isAnswering("c1") }
        store.setMCP(true, chat: "c1")
        store.send("with tools", toChat: "c1")
        XCTAssertTrue(runner.channels[0].closed)
        XCTAssertEqual(runner.channels[1].arguments, ["chat", "session", "--chat", "c1", "--mcp"])
    }

    func testAnAskUsesItsServedSessionAndQuitClosesEverything() {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        let askKey = AskSessionKey(place: .workspace("acme"), session: "claude — api")
        store.warmAsk(askKey, harness: .claude, folder: nil, chatID: nil)
        XCTAssertEqual(runner.channels[0].arguments, [
            "chat", "ask", "--serve", "--workspace", "acme", "--session", "claude — api", "--harness", "claude",
        ])
        store.ask("why?", key: askKey, harness: .claude, chatID: nil)
        XCTAssertEqual(runner.channels[0].writes, [ChatSessionInput.send("why?")])
        store.prewarm(spec)
        store.closeAllSessions()
        XCTAssertTrue(runner.channels.allSatisfy(\.closed))
    }

    func testASendWhileTheWarmSessionStartsShowsItsStatusThenTheTurns() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        store.prewarm(spec)
        let warm = runner.channels[0]
        warm.emit(#"{"type":"status","stage":"connecting","message":"Connecting to main…"}"#)
        await waitForChat { store.sessions.warm?.status != nil }
        let key = store.send("hi", harness: .claude, place: .local)!
        XCTAssertEqual(store.conversation(key).status, "Connecting to main…")
        warm.emit(#"{"type":"status","stage":"starting","message":"Starting Claude…"}"#)
        await waitForChat { store.conversation(key).status == "Starting Claude…" }
        warm.emit(
            #"{"type":"ready","chat":null}"#, #"{"type":"status","stage":"waiting","message":"Claude is thinking…"}"#)
        await waitForChat { store.conversation(key).status == "Claude is thinking…" }
        warm.emit(ChatFixtures.started("c1"), ChatFixtures.text("Hi"))
        await waitForChat { store.conversation("c1").messages.last?.text == "Hi" }
        XCTAssertNil(store.conversation("c1").status)
    }

    func testAReadySessionSaysTheHarnessIsThinkingAtOnce() async {
        let runner = FakeSessionRunner()
        let store = ChatStore(runner: runner)
        store.prewarm(spec)
        runner.channels[0].emit(#"{"type":"ready","chat":null}"#)
        await waitForChat { store.sessions.warm?.isReady == true }
        let key = store.send("hi", harness: .claude, place: .local)!
        XCTAssertEqual(store.conversation(key).status, "Claude is thinking…")
    }

    func testWithoutSessionsNoStatusIsMadeUp() {
        let store = ChatStore(runner: FakeChatRunner(streams: [.init(lines: [], waitsForCancel: true)]))
        let key = store.send("hi", harness: .claude, place: .local)!
        XCTAssertNil(store.conversation(key).status)
        store.stop(key)
    }
}
