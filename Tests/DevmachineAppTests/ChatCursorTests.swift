import XCTest
@testable import DevmachineApp

final class ChatCursorTests: XCTestCase {
    func testTheCursorBlinksWhileAnAnswerComesAndIsGoneAfter() {
        XCTAssertEqual(ChatCursor.markdown("Hi", cursor: true, url: "c:e"), "Hi [▍](c:e)")
        XCTAssertEqual(ChatCursor.markdown("Hi", cursor: false, url: "c:e"), "Hi [\u{2007}](c:e)")
        XCTAssertEqual(ChatCursor.markdown("Hi", cursor: nil, url: "c:e"), "Hi")
        XCTAssertEqual(ChatCursor.markdown("", cursor: true, url: "c:e"), " [▍](c:e)")
    }

    func testItAlternatesEachPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let first = ChatCursor.isOn(at: start, period: 0.5)
        XCTAssertNotEqual(first, ChatCursor.isOn(at: start.addingTimeInterval(0.5), period: 0.5))
        XCTAssertEqual(first, ChatCursor.isOn(at: start.addingTimeInterval(1), period: 0.5))
    }
}
