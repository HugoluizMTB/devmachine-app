import XCTest
@testable import DevmachineCore

final class ChatCommandTests: XCTestCase {
    func testANewChatNamesWhereAndWhat() {
        XCTAssertEqual(
            ChatCommand.send(chatID: nil, place: .workspace("main"), harness: .claude, message: "hi"),
            ["chat", "send", "--workspace", "main", "--harness", "claude", "--", "hi"])
        XCTAssertEqual(
            ChatCommand.send(chatID: nil, place: .local, harness: .codex, message: "-v?"),
            ["chat", "send", "--local", "--harness", "codex", "--", "-v?"])
    }

    func testAContinuedChatTakesItsPlaceFromTheRecord() {
        XCTAssertEqual(
            ChatCommand.send(chatID: "c1", place: .workspace("main"), harness: .claude, message: "and?"),
            ["chat", "send", "--chat", "c1", "--", "and?"])
    }

    func testAsk() {
        XCTAssertEqual(
            ChatCommand.ask(place: .workspace("acme"), session: "claude", chatID: nil, question: "why?"),
            ["chat", "ask", "--workspace", "acme", "--session", "claude", "--", "why?"])
        XCTAssertEqual(
            ChatCommand.ask(
                place: .local, session: "api", folder: "/Users/alice/dev/api", harness: .codex, chatID: "a1",
                question: "and?"),
            ["chat", "ask", "--local", "--session", "api", "--folder", "/Users/alice/dev/api", "--harness", "codex",
             "--chat", "a1", "--", "and?"])
    }

    func testListShowRenameDelete() {
        XCTAssertEqual(ChatCommand.list(), ["chat", "list", "--all", "--json"])
        XCTAssertEqual(ChatCommand.show(id: "c1"), ["chat", "show", "c1", "--json"])
        XCTAssertEqual(ChatCommand.rename(id: "c1", title: "-new"), ["chat", "rename", "c1", "--", "-new"])
        XCTAssertEqual(ChatCommand.delete(id: "c1"), ["chat", "delete", "c1"])
    }
}
