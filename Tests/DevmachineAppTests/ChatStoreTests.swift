import XCTest
import DevmachineCore
@testable import DevmachineApp

final class FakeChatRunner: ChatCommandRunning, @unchecked Sendable {
    struct Script {
        var lines: [String]
        var status: Int32 = 0
        var waitsForCancel = false
        var endsAfterNanoseconds: UInt64 = 0
    }

    private let lock = NSLock()
    private var streams: [Script]
    private var outputs: [String: ChatCommandOutput]
    private var calls: [[String]] = []

    init(streams: [Script] = [], outputs: [String: ChatCommandOutput] = [:]) {
        self.streams = streams
        self.outputs = outputs
    }

    var arguments: [[String]] { lock.withLock { calls } }

    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let script: Script = lock.withLock {
            calls.append(arguments)
            return streams.isEmpty ? Script(lines: []) : streams.removeFirst()
        }
        script.lines.forEach(line)
        if script.endsAfterNanoseconds > 0 { try? await Task.sleep(nanoseconds: script.endsAfterNanoseconds) }
        if script.waitsForCancel {
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
            line(#"{"type":"error","kind":"cancelled","message":"stopped"}"#)
            throw CancellationError()
        }
        return script.status
    }

    func run(_ arguments: [String]) async throws -> ChatCommandOutput {
        lock.withLock {
            calls.append(arguments)
            return outputs[arguments.prefix(2).joined(separator: " ")]
                ?? ChatCommandOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }
}

enum ChatFixtures {
    static func record(
        _ id: String, title: String = "How sessions are rebuilt", workspace: String = "main", kind: String = "chat",
        session: String? = nil, updated: String = "2026-10-15T10:05:00Z"
    ) -> String {
        let sessionField = session.map { #","session":"\#($0)""# } ?? ""
        return #"{"id":"\#(id)","title":"\#(title)","harness":"claude","workspace":"\#(workspace)","folder":"~/chats","harness_session_id":"s1","created_at":"2026-10-15T10:00:00Z","updated_at":"\#(updated)","kind":"\#(kind)"\#(sessionField)}"#
    }

    static func started(_ id: String, kind: String = "chat", session: String? = nil) -> String {
        #"{"type":"started","chat":\#(record(id, kind: kind, session: session))}"#
    }

    static func done(_ id: String, kind: String = "chat", session: String? = nil) -> String {
        #"{"type":"done","chat":\#(record(id, kind: kind, session: session))}"#
    }

    static func text(_ delta: String) -> String { #"{"type":"text","delta":"\#(delta)"}"# }
}

@MainActor
func waitForChat(_ timeout: TimeInterval = 3, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    func testTheFirstSendMovesToTheRealID() async {
        let runner = FakeChatRunner(streams: [.init(lines: [
            ChatFixtures.started("c1"), ChatFixtures.text("It starts"), ChatFixtures.done("c1"),
        ])])
        let store = ChatStore(runner: runner)
        store.workspaces = ["main", "acme"]
        store.draft.text = "how?"
        let key = store.sendFromPane("how does it rebuild?")
        XCTAssertTrue(key?.hasPrefix(ChatStore.pendingPrefix) == true)
        XCTAssertEqual(store.selectedID, key)
        await waitForChat { store.selectedID == "c1" && !store.isAnswering("c1") }
        XCTAssertEqual(store.selectedID, "c1")
        XCTAssertEqual(store.draft.text, "")
        XCTAssertEqual(store.conversation("c1").messages.map(\.text), ["how does it rebuild?", "It starts"])
        XCTAssertEqual(store.records.map(\.id), ["c1"])
        XCTAssertEqual(
            runner.arguments.first,
            ["chat", "send", "--workspace", "main", "--harness", "claude", "--", "how does it rebuild?"])
    }

    func testAFollowUpPassesTheChat() async {
        let runner = FakeChatRunner(streams: [
            .init(lines: [ChatFixtures.started("c1"), ChatFixtures.done("c1")]),
            .init(lines: [ChatFixtures.started("c1"), ChatFixtures.text("more"), ChatFixtures.done("c1")]),
        ])
        let store = ChatStore(runner: runner)
        store.send("one", harness: .codex, place: .local)
        await waitForChat { store.selectedID == "c1" && !store.isAnswering("c1") }
        store.sendFromPane("two")
        await waitForChat { store.conversation("c1").messages.count == 3 && !store.isAnswering("c1") }
        XCTAssertEqual(runner.arguments[0].prefix(5), ["chat", "send", "--local", "--harness", "codex"])
        XCTAssertEqual(runner.arguments[1], ["chat", "send", "--chat", "c1", "--", "two"])
        XCTAssertEqual(store.conversation("c1").messages.last?.text, "more")
    }

    func testALoggedOutHarnessEndsInACard() async {
        let runner = FakeChatRunner(streams: [.init(lines: [
            ChatFixtures.started("c1"),
            #"{"type":"error","kind":"harness-logged-out","message":"Invalid API key · Please run /login"}"#,
        ], status: 1)])
        let store = ChatStore(runner: runner)
        store.send("hi", harness: .claude, place: .workspace("main"))
        await waitForChat { store.conversation("c1").failure != nil }
        XCTAssertEqual(store.conversation("c1").failure?.kind, .harnessLoggedOut)
        XCTAssertFalse(store.isAnswering("c1"))
    }

    func testAStreamThatEndsWithoutDoneFails() async {
        let runner = FakeChatRunner(streams: [.init(lines: [
            ChatFixtures.started("c1"), ChatFixtures.text("par"), "panic: something broke",
        ], status: 2)])
        let store = ChatStore(runner: runner)
        store.send("hi", harness: .claude, place: .workspace("main"))
        await waitForChat { store.conversation("c1").failure != nil }
        XCTAssertEqual(store.conversation("c1").failure, ChatFailure(kind: .harnessFailed, message: "panic: something broke"))
    }

    func testAnOlderCLIAsksForAnUpdate() async {
        let runner = FakeChatRunner(
            streams: [.init(lines: [#"Error: unknown command "chat" for "devmachine""#], status: 1)],
            outputs: ["chat list": ChatCommandOutput(
                stdout: "", stderr: #"Error: unknown command "chat" for "devmachine""#, exitCode: 1)])
        let store = ChatStore(runner: runner)
        await store.refresh()
        XCTAssertEqual(store.listFailure?.kind, .needsNewerCLI)
        let key = store.send("hi", harness: .claude, place: .local)!
        await waitForChat { store.conversation(key).failure != nil }
        XCTAssertEqual(store.conversation(key).failure?.kind, .needsNewerCLI)
        XCTAssertEqual(store.selectedID, key)
    }

    func testStopKeepsThePartialAnswer() async {
        let runner = FakeChatRunner(streams: [.init(
            lines: [ChatFixtures.started("c1"), ChatFixtures.text("half")], waitsForCancel: true)])
        let store = ChatStore(runner: runner)
        store.send("hi", harness: .claude, place: .workspace("main"))
        await waitForChat { store.conversation("c1").messages.last?.text == "half" }
        store.stop("c1")
        XCTAssertFalse(store.isAnswering("c1"))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(store.conversation("c1").failure)
        XCTAssertTrue(store.conversation("c1").wasStopped)
        XCTAssertEqual(store.conversation("c1").messages.last?.text, "half")
    }

    func testRefreshListsChatsAndKeepsAskThreadsOut() async {
        let list = "[\(ChatFixtures.record("c1")),\(ChatFixtures.record("a1", kind: "ask", session: "claude"))]"
        let runner = FakeChatRunner(outputs: ["chat list": ChatCommandOutput(stdout: list, stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        await store.refresh()
        XCTAssertEqual(runner.arguments.prefix(2), [["--format", "json", "config", "show"], ["chat", "list", "--all", "--json"]])
        XCTAssertEqual(store.records.map(\.id), ["c1", "a1"])
        XCTAssertEqual(store.visibleChats.map(\.id), ["c1"])
        let continued = await store.continueAsk("a1")
        XCTAssertTrue(continued)
        XCTAssertTrue(runner.arguments.contains(["chat", "continue", "a1", "--json"]))
        XCTAssertEqual(Set(store.visibleChats.map(\.id)), ["c1", "a1"])
    }

    func testSelectingLoadsTheMessages() async {
        let shown = #"{"chat":\#(ChatFixtures.record("c1")),"messages":[{"role":"user","text":"hi","tools":[]},{"role":"assistant","text":"hello","tools":[]}]}"#
        let runner = FakeChatRunner(outputs: ["chat show": ChatCommandOutput(stdout: shown, stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        store.select("c1")
        await waitForChat { !store.conversation("c1").messages.isEmpty }
        XCTAssertEqual(store.conversation("c1").messages.map(\.text), ["hi", "hello"])
        XCTAssertEqual(runner.arguments.first, ["chat", "show", "c1", "--json"])
    }

    func testRenameAndDelete() async {
        let list = "[\(ChatFixtures.record("c1"))]"
        let runner = FakeChatRunner(outputs: ["chat list": ChatCommandOutput(stdout: list, stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        await store.refresh()
        store.select("c1")
        await store.rename("c1", to: "Caddy reload")
        XCTAssertEqual(store.records.first?.title, "Caddy reload")
        await store.delete("c1")
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(store.selectedID)
        XCTAssertTrue(runner.arguments.contains(["chat", "rename", "c1", "--", "Caddy reload"]))
        XCTAssertTrue(runner.arguments.contains(["chat", "delete", "c1"]))
    }

    func testRetrySendsTheLastQuestionAgain() async {
        let runner = FakeChatRunner(streams: [
            .init(lines: [ChatFixtures.started("c1"),
                          #"{"type":"error","kind":"harness-logged-out","message":"login"}"#], status: 1),
            .init(lines: [ChatFixtures.started("c1"), ChatFixtures.text("ok"), ChatFixtures.done("c1")]),
        ])
        let store = ChatStore(runner: runner)
        store.send("hi", harness: .claude, place: .workspace("main"))
        await waitForChat { store.conversation("c1").failure != nil }
        store.retry("c1")
        await waitForChat { store.conversation("c1").messages.last?.text == "ok" && !store.isAnswering("c1") }
        XCTAssertEqual(store.conversation("c1").messages.map(\.text), ["hi", "ok"])
        XCTAssertEqual(runner.arguments[1], ["chat", "send", "--chat", "c1", "--", "hi"])
    }

    func testAskElsewhereKeepsTheQuestion() async {
        let runner = FakeChatRunner(streams: [.init(lines: [
            ChatFixtures.started("c1"), #"{"type":"error","kind":"harness-logged-out","message":"x"}"#,
        ], status: 1)])
        let store = ChatStore(runner: runner)
        store.send("what does the retry loop do?", harness: .codex, place: .workspace("main"))
        await waitForChat { store.conversation("c1").failure != nil }
        store.askElsewhere("c1")
        XCTAssertNil(store.selectedID)
        XCTAssertEqual(store.draft.text, "what does the retry loop do?")
        XCTAssertEqual(store.draft.harness, .claude)
        XCTAssertEqual(store.openPicker, .workspace)
    }

    func testTitleIsTheFirstLineCutTo60() {
        XCTAssertEqual(ChatStore.title(of: "first\nsecond"), "first")
        XCTAssertEqual(ChatStore.title(of: String(repeating: "a", count: 80)).count, 60)
    }

    func testARealProcessStreamsThroughTheRunner() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("devmachine")
        let lines = [ChatFixtures.started("c9"), ChatFixtures.text("from a process"), ChatFixtures.done("c9")]
        let body = "#!/bin/sh\necho 'note: on stderr' >&2\n" + lines.map { "printf '%s\\n' '\($0)'" }.joined(separator: "\n") + "\n"
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let path = script.path
        let store = ChatStore(runner: ProcessChatCommandRunner(cli: { DevmachineCLI(executable: path) }))
        store.send("hi", harness: .claude, place: .local)
        await waitForChat(10) { store.selectedID == "c9" && !store.isAnswering("c9") }
        XCTAssertEqual(store.conversation("c9").messages.last?.text, "from a process")
        XCTAssertNil(store.conversation("c9").failure)
    }

    func testStoppingARealProcessEndsIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("devmachine")
        let cancelled = #"{"type":"error","kind":"cancelled","message":"stopped"}"#
        let body = """
            #!/bin/sh
            on_term() { kill $!; printf '%s\\n' '\(cancelled)'; exit 130; }
            trap on_term TERM
            printf '%s\\n' '\(ChatFixtures.started("c7"))'
            printf '%s\\n' '\(ChatFixtures.text("half"))'
            sleep 30 &
            wait
            """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let path = script.path
        let store = ChatStore(runner: ProcessChatCommandRunner(cli: { DevmachineCLI(executable: path) }))
        store.send("hi", harness: .claude, place: .local)
        await waitForChat(10) { store.conversation("c7").messages.last?.text == "half" }
        store.stop("c7")
        await waitForChat(10) { store.conversation("c7").wasStopped }
        XCTAssertFalse(store.isAnswering("c7"))
        XCTAssertNil(store.conversation("c7").failure)
        XCTAssertEqual(store.conversation("c7").messages.last?.text, "half")
    }

    func testTheConfigSaysWhereNewChatsRun() async {
        let show = #"{"chat":{"default_workspace":"acme","folder":"~/notes","harness":"codex"}}"#
        let runner = FakeChatRunner(
            streams: [.init(lines: [])],
            outputs: ["--format json": ChatCommandOutput(stdout: show, stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        store.workspaces = ["main", "acme"]
        await store.refresh()
        XCTAssertEqual(store.defaultPlace, .workspace("acme"))
        XCTAssertEqual(store.draftHarness, .codex)
        store.sendFromPane("hi")
        await waitForChat { runner.arguments.contains { $0.prefix(2) == ["chat", "send"] } }
        XCTAssertEqual(
            runner.arguments.first { $0.prefix(2) == ["chat", "send"] },
            ["chat", "send", "--workspace", "acme", "--harness", "codex", "--", "hi"])
    }

    func testARefusedConfigChangeIsReported() async {
        let runner = FakeChatRunner(outputs: ["config set": ChatCommandOutput(
            stdout: "", stderr: "error: chat.default_workspace \"gone\" is not a workspace", exitCode: 1)])
        let store = ChatStore(runner: runner)
        let refusal = await store.saveConfig(ChatCLIConfig(defaultWorkspace: "gone"))
        XCTAssertEqual(refusal, "error: chat.default_workspace \"gone\" is not a workspace")
        XCTAssertTrue(runner.arguments.contains(["config", "set", "chat.default_workspace", "gone"]))
    }

    func testAFailedTurnReadBackShowsItsCard() async {
        let shown = #"{"chat":\#(ChatFixtures.record("c1")),"messages":[{"role":"user","text":"hi","tools":[]},{"role":"assistant","text":"","tools":[],"error":{"kind":"harness-missing","message":"claude: command not found"}}]}"#
        let runner = FakeChatRunner(outputs: ["chat show": ChatCommandOutput(stdout: shown, stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        store.select("c1")
        await waitForChat { store.conversation("c1").failure != nil }
        XCTAssertEqual(store.conversation("c1").failure?.kind, .harnessMissing)
    }

    func testALateEndOfTheLastTurnLeavesTheNextOneAlone() async {
        let runner = FakeChatRunner(streams: [
            .init(lines: [ChatFixtures.started("c1"), ChatFixtures.text("one"), ChatFixtures.done("c1")],
                  endsAfterNanoseconds: 300_000_000),
            .init(lines: [ChatFixtures.started("c1"), ChatFixtures.text("two")], waitsForCancel: true),
        ])
        let store = ChatStore(runner: runner)
        store.send("first", harness: .claude, place: .local)
        await waitForChat { store.selectedID == "c1" && !store.isAnswering("c1") }
        store.send("second", toChat: "c1")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(store.isAnswering("c1"))
        XCTAssertNil(store.conversation("c1").failure)
        store.stop("c1")
    }
}
