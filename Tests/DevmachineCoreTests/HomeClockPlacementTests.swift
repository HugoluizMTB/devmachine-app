import XCTest
@testable import DevmachineCore

final class HomeClockPlacementTests: XCTestCase {
    func testTheClockCentresInHomeWhenItClearsTheCardsByTheGap() {
        XCTAssertTrue(HomeClockPlacement.centresInHome(homeWidth: 1280, cardsMaxX: 336, clockWidth: 420, gap: 24))
        XCTAssertTrue(HomeClockPlacement.centresInHome(homeWidth: 1000, cardsMaxX: 266, clockWidth: 420, gap: 24),
                      "exactly the gap is enough")
    }

    func testTheClockStaysInTheFreeColumnWhenCentringWouldTouchTheCards() {
        XCTAssertFalse(HomeClockPlacement.centresInHome(homeWidth: 1040, cardsMaxX: 336, clockWidth: 420, gap: 24))
        XCTAssertFalse(HomeClockPlacement.centresInHome(homeWidth: 1000, cardsMaxX: 267, clockWidth: 420, gap: 24))
    }
}
