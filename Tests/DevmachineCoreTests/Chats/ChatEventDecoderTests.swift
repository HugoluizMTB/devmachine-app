import XCTest
@testable import DevmachineCore

final class ChatEventDecoderTests: XCTestCase {
    private let record = #"{"id":"c1","title":"How sessions are rebuilt","harness":"claude","workspace":"main","folder":"~/chats","harness_session_id":"s-1","created_at":"2026-10-15T10:00:00Z","updated_at":"2026-10-15T10:05:00.123456789-03:00","kind":"chat"}"#

    func testStartedCarriesTheRecord() throws {
        guard case let .started(chat)? = ChatEventDecoder.decode(#"{"type":"started","chat":\#(record)}"#) else {
            return XCTFail("not started")
        }
        XCTAssertEqual(chat.id, "c1")
        XCTAssertEqual(chat.harness, .claude)
        XCTAssertEqual(chat.workspace, "main")
        XCTAssertEqual(chat.folder, "~/chats")
        XCTAssertEqual(chat.harnessSessionID, "s-1")
        XCTAssertFalse(chat.isLocal)
        XCTAssertEqual(chat.createdAt, ISO8601DateFormatter().date(from: "2026-10-15T10:00:00Z"))
        XCTAssertEqual(
            chat.updatedAt.timeIntervalSince1970,
            ISO8601DateFormatter().date(from: "2026-10-15T13:05:00Z")!.timeIntervalSince1970 + 0.123,
            accuracy: 0.001)
    }

    func testTextToolAndDone() {
        XCTAssertEqual(ChatEventDecoder.decode(#"{"type":"text","delta":"It starts "}"#), .text("It starts "))
        XCTAssertEqual(
            ChatEventDecoder.decode(#"{"type":"tool","name":"Read","summary":"internal/sessions/build.go"}"#),
            .tool(ChatTool(name: "Read", summary: "internal/sessions/build.go")))
        guard case .done? = ChatEventDecoder.decode(#"{"type":"done","chat":\#(record)}"#) else {
            return XCTFail("not done")
        }
    }

    func testErrorKinds() {
        XCTAssertEqual(
            ChatEventDecoder.decode(#"{"type":"error","kind":"harness-logged-out","message":"Please run /login"}"#),
            .error(ChatFailure(kind: .harnessLoggedOut, message: "Please run /login")))
        let wire = [
            "unreachable": ChatFailureKind.unreachable, "login-refused": .loginRefused,
            "host-key-rejected": .hostKeyRejected, "harness-missing": .harnessMissing,
            "harness-failed": .harnessFailed, "cancelled": .cancelled, "session-not-found": .sessionNotFound,
            "transcript-not-found": .transcriptNotFound, "harness-unsupported": .harnessUnsupported,
        ]
        for (raw, kind) in wire {
            XCTAssertEqual(ChatFailureKind(wire: raw), kind, raw)
        }
        XCTAssertEqual(ChatFailureKind(wire: "brand-new"), .other("brand-new"))
    }

    func testNonJSONLinesAreNotEvents() {
        XCTAssertNil(ChatEventDecoder.decode("warning: agent has no keys"))
        XCTAssertNil(ChatEventDecoder.decode(""))
        XCTAssertNil(ChatEventDecoder.decode(#"{"type":"thinking"}"#))
        XCTAssertNil(ChatEventDecoder.decode("{not json"))
    }

    func testUnknownCommandMeansAnOlderCLI() {
        let failure = ChatFailure.fromExit(
            status: 1, output: "Error: unknown command \"chat\" for \"devmachine\"\nRun 'devmachine --help' for usage.")
        XCTAssertEqual(failure.kind, .needsNewerCLI)
        XCTAssertEqual(ChatFailure.fromExit(status: 2, output: "boom").kind, .harnessFailed)
        XCTAssertTrue(ChatFailure.fromExit(status: 137, output: "").message.contains("137"))
    }

    func testLocalWorkspaceAndAskFields() throws {
        let data = Data(#"{"id":"a1","title":"why?","harness":"codex","workspace":"local","kind":"ask","session":"claude — api","source_session_id":"src","mode":"transcript","created_at":"2026-10-15T10:00:00Z","updated_at":"2026-10-15T10:00:00Z"}"#.utf8)
        let chat = try JSONDecoder().decode(ChatRecord.self, from: data)
        XCTAssertTrue(chat.isLocal)
        XCTAssertEqual(chat.place, .local)
        XCTAssertTrue(chat.isAsk)
        XCTAssertEqual(chat.session, "claude — api")
        XCTAssertEqual(chat.sourceSessionID, "src")
        XCTAssertEqual(chat.mode, "transcript")
    }

    func testListAsArrayOrObject() throws {
        XCTAssertEqual(try ChatListDecoder.decode(Data("[\(record)]".utf8)).map(\.id), ["c1"])
        XCTAssertEqual(try ChatListDecoder.decode(Data(#"{"chats":[\#(record)]}"#.utf8)).map(\.id), ["c1"])
        XCTAssertEqual(try ChatListDecoder.decode(Data(#"{"chats":null}"#.utf8)), [])
    }

    func testShowNestedOrFlat() throws {
        let messages = #"[{"role":"user","text":"hi","tools":[],"at":"2026-10-15T10:00:00Z"},{"role":"assistant","text":"hello","tools":[{"name":"Read","summary":"a.go"}],"at":"2026-10-15T10:00:01Z"}]"#
        let nested = try JSONDecoder().decode(
            ChatShow.self, from: Data(#"{"chat":\#(record),"messages":\#(messages)}"#.utf8))
        XCTAssertEqual(nested.record.id, "c1")
        XCTAssertEqual(nested.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(nested.messages[1].tools, [ChatTool(name: "Read", summary: "a.go")])
        let flat = String(record.dropLast()) + #","messages":\#(messages)}"#
        let decoded = try JSONDecoder().decode(ChatShow.self, from: Data(flat.utf8))
        XCTAssertEqual(decoded.record.title, "How sessions are rebuilt")
        XCTAssertEqual(decoded.messages.count, 2)
    }

    func testToolsMayBePlainLines() throws {
        let message = try JSONDecoder().decode(
            ChatMessage.self, from: Data(#"{"role":"assistant","text":"x","tools":["Read a.go"]}"#.utf8))
        XCTAssertEqual(message.tools.first?.line, "Read a.go")
    }

    func testAFailedTurnInTheLocalCopy() throws {
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(
            #"{"role":"assistant","text":"","tools":[],"error":{"kind":"harness-logged-out","message":"Not logged in"}}"#.utf8))
        XCTAssertEqual(message.error, ChatFailure(kind: .harnessLoggedOut, message: "Not logged in"))
    }

    func testAUsageErrorIsARefusal() {
        let failure = ChatFailure.fromExit(status: 1, output: "error: no workspace named \"nope\", and none is configured")
        XCTAssertEqual(failure.kind, .refused)
        XCTAssertEqual(
            ChatFailurePresentation(failure: failure, harness: .claude, place: .workspace("nope")).body,
            "No workspace named \"nope\", and none is configured")
    }

    func testExcerpts() throws {
        let chat = try JSONDecoder().decode(ChatRecord.self, from: Data(
            #"{"id":"c_1","kind":"ask","mode":"transcript","excerpts":3,"created_at":"2026-10-15T10:00:00Z"}"#.utf8))
        XCTAssertEqual(chat.excerpts, 3)
    }
}
