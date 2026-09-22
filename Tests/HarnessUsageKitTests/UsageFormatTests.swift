import XCTest
@testable import HarnessUsageKit

final class UsageFormatTests: XCTestCase {
    func testBillions() {
        XCTAssertEqual(UsageFormat.tokens(1_280_000_000), "1.28B")
    }

    func testMillions() {
        XCTAssertEqual(UsageFormat.tokens(740_310_000), "740.31M")
        XCTAssertEqual(UsageFormat.tokens(11_220_000), "11.22M")
    }

    func testBelowThousand() {
        XCTAssertEqual(UsageFormat.tokens(500), "500")
    }

    func testPlanLabelMax20x() {
        XCTAssertEqual(UsageFormat.planLabel("default_claude_max_20x"), "Max 20x")
    }

    func testPlanLabelPro() {
        XCTAssertEqual(UsageFormat.planLabel("default_claude_pro"), "Pro")
    }
}
