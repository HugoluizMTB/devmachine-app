import XCTest
@testable import DevmachineApp

final class ContextPollRuleTests: XCTestCase {
    func testPollsOnlyWhenTheContextTabShowsAWidgetThatReadsIt() {
        XCTAssertTrue(ContextPollRule.shouldPoll(showsPanel: true, collapsed: false, tab: .context, hasTarget: true, boardNeedsContext: true))
        XCTAssertFalse(ContextPollRule.shouldPoll(showsPanel: true, collapsed: false, tab: .context, hasTarget: true, boardNeedsContext: false))
        XCTAssertFalse(ContextPollRule.shouldPoll(showsPanel: true, collapsed: true, tab: .context, hasTarget: true, boardNeedsContext: true))
        XCTAssertFalse(ContextPollRule.shouldPoll(showsPanel: true, collapsed: false, tab: .git, hasTarget: true, boardNeedsContext: true))
        XCTAssertFalse(ContextPollRule.shouldPoll(showsPanel: false, collapsed: false, tab: .context, hasTarget: true, boardNeedsContext: true))
        XCTAssertFalse(ContextPollRule.shouldPoll(showsPanel: true, collapsed: false, tab: .context, hasTarget: false, boardNeedsContext: true))
    }
}
