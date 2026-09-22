import XCTest
@testable import HarnessUsageKit

final class UsageParserTests: XCTestCase {
    func testParseUsageClassifiesLines() {
        let text = """
        Session (5 hour): 30% used, resets Sep 12 at 10:50pm
        Weekly (7 day): 59% used, resets Sep 15 at 12:00am
        Weekly Opus (7 day): 48% used
        This is just a random line of prose
        """

        let blocks = UsageParser.parseUsage(text)

        XCTAssertEqual(blocks.count, 3)

        XCTAssertEqual(blocks[0].kind, .session)
        XCTAssertEqual(blocks[0].percent, 30)
        XCTAssertFalse(blocks[0].resets.isEmpty)

        XCTAssertEqual(blocks[1].kind, .weeklyAll)
        XCTAssertEqual(blocks[1].percent, 59)
        XCTAssertFalse(blocks[1].resets.isEmpty)

        XCTAssertEqual(blocks[2].kind, .weeklyModel)
        XCTAssertEqual(blocks[2].percent, 48)
        XCTAssertEqual(blocks[2].resets, "")
    }

    func testPlanNameReadsOrganizationRateLimitTier() {
        let json = #"{"oauthAccount":{"organizationRateLimitTier":"Max 20x"}}"#
        XCTAssertEqual(UsageParser.planName(fromClaudeJSON: json), "Max 20x")
    }

    func testPlanNameReturnsNilForBadJSON() {
        XCTAssertNil(UsageParser.planName(fromClaudeJSON: "not json"))
    }

    func testPlanNameReturnsNilWhenFieldMissing() {
        let json = #"{"oauthAccount":{}}"#
        XCTAssertNil(UsageParser.planName(fromClaudeJSON: json))
    }
}
