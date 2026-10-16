import XCTest
@testable import DevmachineCore

final class AskThreadTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func ask(_ id: String, session: String, workspace: String = "acme", minutes: Double) -> ChatRecord {
        let date = base.addingTimeInterval(minutes * 60)
        return ChatRecord(
            id: id, title: id, harness: .claude, workspace: workspace, createdAt: date, updatedAt: date,
            kind: ChatRecord.askKind, session: session)
    }

    func testModeFollowsTheHarness() {
        XCTAssertEqual(AskMode(harness: .claude), .supported(.claude))
        XCTAssertEqual(AskMode(harness: .codex), .supported(.codex))
        XCTAssertEqual(AskMode(harness: .pi), .unsupported(.pi))
        XCTAssertEqual(AskMode(harness: .claude).subtitle, "about this session · Claude")
        XCTAssertEqual(AskMode(harness: .codex).subtitle, "about this session · Codex")
        XCTAssertEqual(AskMode(harness: .pi).subtitle, "Ask is not available for Pi yet")
        XCTAssertFalse(AskMode(harness: nil).isSupported)
    }

    func testTheNewestAskOfThatSession() {
        let chat = ChatRecord(
            id: "plain", title: "x", harness: .claude, workspace: "acme",
            createdAt: base.addingTimeInterval(9000), updatedAt: base.addingTimeInterval(9000))
        let records = [
            ask("old", session: "claude", minutes: 1), ask("new", session: "claude", minutes: 5),
            ask("other", session: "codex", minutes: 9), ask("local", session: "claude", workspace: "local", minutes: 9),
            chat,
        ]
        let key = AskSessionKey(place: .workspace("acme"), session: "claude")
        XCTAssertEqual(AskThreadPicker.latest(in: records, key: key, after: nil)?.id, "new")
        XCTAssertEqual(
            AskThreadPicker.latest(in: records, key: AskSessionKey(place: .local, session: "claude"), after: nil)?.id,
            "local")
    }

    func testAResetHidesOlderThreads() {
        let records = [ask("old", session: "claude", minutes: 1)]
        let key = AskSessionKey(place: .workspace("acme"), session: "claude")
        XCTAssertNil(AskThreadPicker.latest(in: records, key: key, after: base.addingTimeInterval(120)))
    }
}
