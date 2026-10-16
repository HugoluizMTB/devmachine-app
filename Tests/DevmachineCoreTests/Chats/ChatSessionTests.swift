import XCTest
@testable import DevmachineCore

final class ChatSessionTests: XCTestCase {
    func testTheSessionCommandNamesTheChatOrWhereANewOneRuns() {
        let spec = ChatSessionSpec(harness: .codex, place: .workspace("main"), mcp: true)
        XCTAssertEqual(
            ChatCommand.session(chatID: nil, spec: spec, mcp: true),
            ["chat", "session", "--workspace", "main", "--harness", "codex", "--mcp"])
        XCTAssertEqual(ChatCommand.session(chatID: "c1", spec: spec, mcp: nil), ["chat", "session", "--chat", "c1"])
        XCTAssertEqual(
            ChatCommand.askServe(place: .local, session: "api", folder: "/w", harness: .claude, chatID: "a1"),
            ["chat", "ask", "--serve", "--local", "--session", "api", "--folder", "/w", "--harness", "claude",
             "--chat", "a1"])
    }

    func testReadyClosedAndTurnEventsAreTold() {
        XCTAssertEqual(ChatSessionLine.decode(#"{"type":"ready","chat":null}"#), .ready(nil))
        guard case let .ready(chat?) = ChatSessionLine.decode(#"{"type":"ready","chat":{"id":"c1"}}"#) else {
            return XCTFail("no chat on ready")
        }
        XCTAssertEqual(chat.id, "c1")
        XCTAssertEqual(ChatSessionLine.decode(#"{"type":"closed","reason":"idle"}"#), .closed("idle"))
        XCTAssertEqual(ChatSessionLine.decode(#"{"type":"text","delta":"hi"}"#), .event(.text("hi")))
        XCTAssertNil(ChatSessionLine.decode("ssh: warning"))
    }

    func testInputLinesAreOneJSONObjectEach() throws {
        let line = ChatSessionInput.send("say \"hi\"\nthen stop")
        XCTAssertFalse(line.contains("\n"))
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String]
        XCTAssertEqual(object, ["type": "send", "text": "say \"hi\"\nthen stop"])
        XCTAssertEqual(ChatSessionInput.cancel, #"{"type":"cancel"}"#)
    }

    func testAnOlderCLIIsToldFromItsRefusal() {
        XCTAssertTrue(ChatSessionLine.isUnsupported(#"Error: unknown command "session" for "devmachine chat""#))
        XCTAssertTrue(ChatSessionLine.isUnsupported("error: unknown flag: --serve"))
        XCTAssertTrue(ChatSessionLine.isUnsupported("error: unknown flag: --local"))
        XCTAssertFalse(ChatSessionLine.isUnsupported("ssh: connect to host example.com: timed out"))
    }
}
