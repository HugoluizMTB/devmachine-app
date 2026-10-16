import XCTest
@testable import DevmachineCore

final class ChatGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-15T15:00:00Z")!

    private func chat(_ id: String, hoursAgo: Double, title: String = "t") -> ChatRecord {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        return ChatRecord(id: id, title: title, harness: .claude, workspace: "main", createdAt: date, updatedAt: date)
    }

    func testGroupsByDayNewestFirst() {
        let chats = [
            chat("old", hoursAgo: 24 * 30), chat("today-early", hoursAgo: 10), chat("yesterday", hoursAgo: 20),
            chat("today", hoursAgo: 1), chat("week", hoursAgo: 24 * 4),
        ]
        let groups = ChatGrouping.groups(chats, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "Previous 7 days", "Older"])
        XCTAssertEqual(groups[0].chats.map(\.id), ["today", "today-early"])
        XCTAssertEqual(groups[1].chats.map(\.id), ["yesterday"])
        XCTAssertEqual(groups[2].chats.map(\.id), ["week"])
        XCTAssertEqual(groups[3].chats.map(\.id), ["old"])
    }

    func testEmptyGroupsAreLeftOut() {
        XCTAssertEqual(ChatGrouping.groups([chat("a", hoursAgo: 1)], now: now, calendar: calendar).map(\.title), ["Today"])
        XCTAssertEqual(ChatGrouping.groups([], now: now, calendar: calendar), [])
    }

    func testSearchIsByTitleIgnoringCase() {
        let chats = [chat("a", hoursAgo: 1, title: "Caddy reload"), chat("b", hoursAgo: 1, title: "tmux keys")]
        XCTAssertEqual(ChatGrouping.filter(chats, query: "CADDY").map(\.id), ["a"])
        XCTAssertEqual(ChatGrouping.filter(chats, query: "  ").map(\.id), ["a", "b"])
    }

    func testShortAges() {
        XCTAssertEqual(ChatGrouping.age(of: now.addingTimeInterval(-20), now: now), "now")
        XCTAssertEqual(ChatGrouping.age(of: now.addingTimeInterval(-300), now: now), "5m")
        XCTAssertEqual(ChatGrouping.age(of: now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(ChatGrouping.age(of: now.addingTimeInterval(-86_400 * 3), now: now), "3d")
        XCTAssertEqual(ChatGrouping.age(of: now.addingTimeInterval(-86_400 * 21), now: now), "3w")
        XCTAssertEqual(ChatGrouping.age(of: now.addingTimeInterval(60), now: now), "now")
    }
}

final class ChatListNavigationTests: XCTestCase {
    func testArrowsWalkTheListAndStopAtItsEnds() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(ChatListNavigation.neighbor(of: "a", in: ids, step: 1), "b")
        XCTAssertEqual(ChatListNavigation.neighbor(of: "b", in: ids, step: -1), "a")
        XCTAssertEqual(ChatListNavigation.neighbor(of: "c", in: ids, step: 1), "c")
        XCTAssertEqual(ChatListNavigation.neighbor(of: "a", in: ids, step: -1), "a")
    }

    func testWithNothingSelectedTheArrowsStartAtAnEnd() {
        XCTAssertEqual(ChatListNavigation.neighbor(of: nil, in: ["a", "b"], step: 1), "a")
        XCTAssertEqual(ChatListNavigation.neighbor(of: "gone", in: ["a", "b"], step: -1), "b")
        XCTAssertNil(ChatListNavigation.neighbor(of: nil, in: [], step: 1))
    }
}
