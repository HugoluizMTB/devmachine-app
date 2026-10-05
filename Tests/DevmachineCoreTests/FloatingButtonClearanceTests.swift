import XCTest
@testable import DevmachineCore

final class FloatingButtonClearanceTests: XCTestCase {
    /// The collapsed sidebar's button, 18 points under a 28-point title bar and 14 from the edge.
    private func button(scale: Double) -> CGRect {
        CGRect(x: 14 * scale, y: 28 + 18 * scale, width: 32 * scale, height: 32 * scale)
    }

    func testContentUnderTheButtonMovesDownBelowItWithTheGap() {
        let inset = FloatingButtonClearance.topInset(
            button: button(scale: 1), contentMinX: 24, contentMinY: 24, gap: 8)
        XCTAssertEqual(inset, 28 + 18 + 32 + 8 - 24)
    }

    func testAtEveryTextSizeTheContentStartsBelowTheButton() {
        for scale in [0.8, 1, 1.15, 1.3, 1.6] {
            let button = button(scale: scale)
            let padding = 24 * scale, gap = 8 * scale
            let inset = FloatingButtonClearance.topInset(
                button: button, contentMinX: padding, contentMinY: padding, gap: gap)
            XCTAssertGreaterThanOrEqual(padding + inset, button.maxY + gap - 0.001, "\(scale)")
        }
    }

    func testContentThatStartsRightOfTheButtonStaysWhereItIs() {
        XCTAssertEqual(
            FloatingButtonClearance.topInset(button: button(scale: 1), contentMinX: 60, contentMinY: 24, gap: 8), 0)
    }

    func testContentAlreadyBelowTheButtonStaysWhereItIs() {
        XCTAssertEqual(
            FloatingButtonClearance.topInset(button: button(scale: 1), contentMinX: 24, contentMinY: 120, gap: 8), 0)
    }

    func testNoButtonMovesNothing() {
        XCTAssertEqual(FloatingButtonClearance.topInset(button: nil, contentMinX: 24, contentMinY: 24, gap: 8), 0)
    }
}
