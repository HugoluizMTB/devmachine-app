import XCTest
@testable import DevmachineCore

final class CanvasLayoutTests: XCTestCase {
    private func frame(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> BoardFrame { BoardFrame(x: x, y: y, w: w, h: h) }

    private func medium(_ x: Int, _ y: Int) -> BoardFrame { frame(x, y, 320, 160) }

    func testSnapRoundsToTheNearestEightPoints() {
        XCTAssertEqual(CanvasLayout.snapped(0), 0)
        XCTAssertEqual(CanvasLayout.snapped(3.9), 0)
        XCTAssertEqual(CanvasLayout.snapped(4), 8)
        XCTAssertEqual(CanvasLayout.snapped(13), 16)
        XCTAssertEqual(CanvasLayout.snapped(-3), 0)
    }

    func testPresetsAreUnitsOfEightyPoints() {
        XCTAssertEqual(CanvasLayout.presetSize("small"), CanvasSize(w: 160, h: 160))
        XCTAssertEqual(CanvasLayout.presetSize("medium"), CanvasSize(w: 320, h: 160))
        XCTAssertEqual(CanvasLayout.presetSize("large"), CanvasSize(w: 320, h: 320))
        XCTAssertEqual(CanvasLayout.presetSize("wide"), CanvasSize(w: 640, h: 160))
        XCTAssertEqual(CanvasLayout.presetSize("tall"), CanvasSize(w: 160, h: 320))
        XCTAssertNil(CanvasLayout.presetSize("custom"))
    }

    func testTheMinimumKeepsEveryAcceptedPresetReachable() {
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: ["small", "medium", "wide"]), CanvasSize(w: 160, h: 160))
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: ["wide", "tall"]), CanvasSize(w: 160, h: 160))
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: ["large"]), CanvasSize(w: 320, h: 320))
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: ["wide"]), CanvasSize(w: 640, h: 160))
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: []), CanvasSize(w: 160, h: 160))
    }

    func testASizeIsNamedOnlyWhenItIsAnAcceptedPreset() {
        XCTAssertEqual(CanvasLayout.sizeName(CanvasSize(w: 320, h: 160), sizes: ["small", "medium"]), "medium")
        XCTAssertEqual(CanvasLayout.sizeName(CanvasSize(w: 328, h: 160), sizes: ["small", "medium"]), "custom")
        XCTAssertEqual(CanvasLayout.sizeName(CanvasSize(w: 640, h: 160), sizes: ["small", "medium"]), "custom")
    }

    func testResizeSnapsAndNeverGoesUnderTheMinimum() {
        let start = frame(24, 24, 320, 160)
        let minimum = CanvasSize(w: 160, h: 160)
        XCTAssertEqual(CanvasLayout.resized(start, width: 333, height: 171, minimum: minimum), frame(24, 24, 336, 168))
        XCTAssertEqual(CanvasLayout.resized(start, width: 40, height: 10, minimum: minimum), frame(24, 24, 160, 160))
    }

    func testClampMovesTheDrawingOnScreenOnly() {
        let stored = frame(1200, 900, 320, 160)
        let drawn = CanvasLayout.clamped(stored, in: CGSize(width: 1000, height: 700))
        XCTAssertEqual(drawn, CGRect(x: 680, y: 540, width: 320, height: 160))
        XCTAssertEqual(stored, frame(1200, 900, 320, 160))
        let wider = CanvasLayout.clamped(frame(100, 0, 1200, 160), in: CGSize(width: 1000, height: 700))
        XCTAssertEqual(wider.minX, 0)
    }

    func testAMoveWithNothingNearSnapsToTheGrid() {
        let move = CanvasLayout.moved(frame(0, 0, 160, 160), to: CGPoint(x: 101, y: 53), among: [])
        XCTAssertEqual(move.frame, frame(104, 56, 160, 160))
        XCTAssertEqual(move.guides, [])
    }

    func testAnEdgeWithinSixPointsSnapsToTheOtherWidgetsEdge() {
        let other = frame(200, 400, 320, 160)
        let move = CanvasLayout.moved(frame(0, 0, 160, 160), to: CGPoint(x: 204.5, y: 37), among: [other])
        XCTAssertEqual(move.frame.x, 200)
        XCTAssertEqual(move.frame.y, 40)
        XCTAssertEqual(move.guides, [CanvasGuide(axis: .vertical, position: 200, start: 40, end: 560)])
    }

    func testCentresAlignToo() {
        let other = frame(0, 0, 320, 160)
        let move = CanvasLayout.moved(frame(0, 0, 160, 160), to: CGPoint(x: 83, y: 400), among: [other])
        XCTAssertEqual(move.frame.x, 80)
        XCTAssertEqual(move.guides.first?.axis, .vertical)
        XCTAssertEqual(move.guides.first?.position, 160)
    }

    func testAMoveNeverLeavesTheCanvasOrigin() {
        let move = CanvasLayout.moved(frame(0, 0, 160, 160), to: CGPoint(x: -50, y: -9), among: [])
        XCTAssertEqual(move.frame.x, 0)
        XCTAssertEqual(move.frame.y, 0)
    }

    func testTheFirstFreeSpotKeepsEightPointsFromEveryOtherWidget() {
        let size = CanvasSize(w: 320, h: 160)
        XCTAssertEqual(CanvasLayout.firstFreeSpot(for: size, avoiding: []), medium(24, 24))
        XCTAssertEqual(CanvasLayout.firstFreeSpot(for: size, avoiding: [medium(24, 24)]), medium(352, 24))
        XCTAssertEqual(
            CanvasLayout.firstFreeSpot(for: size, avoiding: [medium(24, 24), medium(1008, 24)]), medium(352, 24))
        XCTAssertEqual(
            CanvasLayout.firstFreeSpot(
                for: size, avoiding: [medium(24, 24), medium(352, 24), medium(680, 24), medium(1008, 24)]),
            medium(24, 192))
    }

    func testTheFirstFreeSpotWrapsWhenTheBandIsNarrow() {
        let spot = CanvasLayout.firstFreeSpot(for: CanvasSize(w: 320, h: 160), avoiding: [medium(24, 24)], bandWidth: 400)
        XCTAssertEqual(spot, medium(24, 192))
    }

    func testAWidgetWiderThanTheBandStillGoesAtTheMargin() {
        let spot = CanvasLayout.firstFreeSpot(for: CanvasSize(w: 2000, h: 160), avoiding: [])
        XCTAssertEqual(spot, frame(24, 24, 2000, 160))
    }

    func testDisplayScaleNeverReachesTheStoredFrame() {
        let scale = 1.3
        let drawn = CanvasLayout.toDisplay(frame(24, 24, 320, 160).rect, scale: scale)
        XCTAssertEqual(drawn.width, 416, accuracy: 0.001)
        let translation = CanvasLayout.toBoard(CGSize(width: 104, height: 52), scale: scale)
        let start = frame(24, 24, 320, 160)
        let move = CanvasLayout.moved(
            start, to: CGPoint(x: Double(start.x) + translation.width, y: Double(start.y) + translation.height), among: [])
        XCTAssertEqual(move.frame, frame(104, 64, 320, 160))
    }
}
