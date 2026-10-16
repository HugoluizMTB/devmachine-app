import XCTest
@testable import DevmachineCore

final class ChatConversationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ id: String = "c1") -> ChatRecord {
        ChatRecord(id: id, title: "t", harness: .claude, workspace: "main", createdAt: start, updatedAt: start)
    }

    func testTheLatestStatusShowsUntilTheAnswerStarts() {
        var conversation = ChatConversation()
        conversation.begin(userText: "hi", at: start)
        conversation.apply(.status(ChatStatus(stage: "connecting", message: "Connecting to main…")))
        XCTAssertEqual(conversation.status, "Connecting to main…")
        conversation.apply(.status(ChatStatus(stage: "starting", message: "Starting Claude…")))
        XCTAssertEqual(conversation.status, "Starting Claude…")
        conversation.apply(.text("Hel"))
        XCTAssertNil(conversation.status)
        conversation.apply(.done(record()))
        XCTAssertNil(conversation.status)
    }

    func testAToolDeniedErrorStopOrExitClearsTheStatus() {
        let waiting = ChatEvent.status(ChatStatus(stage: "waiting", message: "Claude is thinking…"))
        let enders: [(inout ChatConversation) -> Void] = [
            { $0.apply(.tool(ChatTool(name: "Read", summary: "a.go"))) },
            { $0.apply(.denied(ChatTool(name: "Bash", summary: "ls"))) },
            { $0.apply(.error(ChatFailure(kind: .harnessFailed, message: "no"))) },
            { $0.stop() },
            { $0.processEnded(status: 1, output: "") },
        ]
        for end in enders {
            var conversation = ChatConversation()
            conversation.begin(userText: "hi", at: start)
            conversation.apply(waiting)
            end(&conversation)
            XCTAssertNil(conversation.status)
        }
        var idle = ChatConversation()
        idle.apply(waiting)
        XCTAssertNil(idle.status)
    }

    func testDeltasBuildOneAnswerAndToolsJoinIt() {
        var conversation = ChatConversation()
        conversation.begin(userText: "how?", at: start)
        conversation.apply(.started(record()))
        conversation.apply(.tool(ChatTool(name: "Read", summary: "a.go")))
        conversation.apply(.text("It "))
        conversation.apply(.text("starts."))
        XCTAssertTrue(conversation.isStreaming)
        XCTAssertEqual(conversation.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(conversation.messages[1].text, "It starts.")
        XCTAssertEqual(conversation.messages[1].tools, [ChatTool(name: "Read", summary: "a.go")])
        conversation.apply(.done(record()))
        XCTAssertFalse(conversation.isStreaming)
        XCTAssertNil(conversation.failure)
    }

    func testADeniedToolJoinsTheAnswer() {
        var conversation = ChatConversation()
        conversation.begin(userText: "run the tests", at: start)
        conversation.apply(.denied(ChatTool(name: "Bash", summary: "go test ./...")))
        conversation.apply(.text("I could not run them."))
        XCTAssertEqual(conversation.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(conversation.messages[1].denied, [ChatTool(name: "Bash", summary: "go test ./...")])
        XCTAssertTrue(conversation.isStreaming)
    }

    func testASecondTurnStartsANewAnswer() {
        var conversation = ChatConversation()
        conversation.begin(userText: "one", at: start)
        conversation.apply(.text("first"))
        conversation.apply(.done(record()))
        conversation.begin(userText: "two", at: start)
        conversation.apply(.text("second"))
        XCTAssertEqual(conversation.messages.map(\.text), ["one", "first", "two", "second"])
        XCTAssertEqual(conversation.lastUserText, "two")
    }

    func testAnErrorEndsTheTurnWithACard() {
        var conversation = ChatConversation()
        conversation.begin(userText: "hi", at: start)
        conversation.apply(.error(ChatFailure(kind: .harnessLoggedOut, message: "Please run /login")))
        XCTAssertFalse(conversation.isStreaming)
        XCTAssertEqual(conversation.failure?.kind, .harnessLoggedOut)
        conversation.begin(userText: "hi", at: start)
        XCTAssertNil(conversation.failure)
    }

    func testCancelledKeepsThePartialAnswerWithoutACard() {
        var conversation = ChatConversation()
        conversation.begin(userText: "hi", at: start)
        conversation.apply(.text("half"))
        conversation.apply(.error(ChatFailure(kind: .cancelled, message: "")))
        XCTAssertNil(conversation.failure)
        XCTAssertTrue(conversation.wasStopped)
        XCTAssertEqual(conversation.messages.last?.text, "half")
    }

    func testAStreamThatEndsWithoutDoneFails() {
        var conversation = ChatConversation()
        conversation.begin(userText: "hi", at: start)
        conversation.apply(.text("par"))
        conversation.processEnded(status: 1, output: "panic: runtime error")
        XCTAssertFalse(conversation.isStreaming)
        XCTAssertEqual(conversation.failure, ChatFailure(kind: .harnessFailed, message: "panic: runtime error"))
    }

    func testProcessEndAfterDoneChangesNothing() {
        var conversation = ChatConversation()
        conversation.begin(userText: "hi", at: start)
        conversation.apply(.done(record()))
        conversation.processEnded(status: 0, output: "")
        XCTAssertNil(conversation.failure)
    }

    func testStop() {
        var conversation = ChatConversation()
        conversation.begin(userText: "hi", at: start)
        conversation.stop()
        XCTAssertFalse(conversation.isStreaming)
        XCTAssertTrue(conversation.wasStopped)
    }

    func testHarnessTitlesAndPackages() {
        XCTAssertEqual(ChatHarness.title(.claude), "Claude")
        XCTAssertEqual(ChatHarness.title(.codex), "Codex")
        XCTAssertEqual(ChatHarness.title(.pi), "Pi")
        XCTAssertEqual(ChatHarness.package(.claude), "claude-code")
        XCTAssertEqual(ChatHarness.package(.codex), "codex")
    }
}
