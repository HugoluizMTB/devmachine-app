import XCTest
@testable import DevmachineCore

final class CanvasAutoHeightTests: XCTestCase {
    private func widget(_ id: String, size: String = "custom", _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> BoardWidget {
        BoardWidget(id: id, type: "devmachine-app/summary", frame: BoardFrame(x: x, y: y, w: w, h: h), size: size, z: 1)
    }

    private func place(_ id: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CanvasPlacement {
        CanvasPlacement(id: id, x: x, y: y, w: w, h: h)
    }

    func testAGrowingViewHasNoPresetHeightMinimum() {
        let sizes = ["small", "medium", "large"]
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: sizes, grows: true), CanvasSize(w: 160, h: 40))
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: ["wide"], grows: true), CanvasSize(w: 640, h: 40))
        XCTAssertEqual(CanvasLayout.minimumSize(sizes: sizes, grows: false), CanvasSize(w: 160, h: 160))
    }

    func testAutoDrawsAtTheContentHeight() {
        let auto = widget("summary", size: "auto", 24, 24, 336, 0)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: auto, content: 44, grows: true), 44)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: auto, content: 900, grows: true), 900)
    }

    func testAStoredHeightIsACapOnAGrowingView() {
        let capped = widget("summary", 24, 24, 336, 160)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: capped, content: 44, grows: true), 44)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: capped, content: 500, grows: true), 160)
        let tiny = widget("summary", 24, 24, 336, 8)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: tiny, content: 500, grows: true), 40)
    }

    func testANonGrowingViewKeepsItsStoredHeight() {
        let clock = widget("clock", 24, 24, 336, 160)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: clock, content: 44, grows: false), 160)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: clock, content: nil, grows: false), 160)
    }

    func testBeforeTheContentIsMeasuredACapHoldsAndAutoTakesTheRowFloor() {
        XCTAssertEqual(CanvasLayout.drawnHeight(of: widget("a", 0, 0, 200, 160), content: nil, grows: true), 160)
        XCTAssertEqual(CanvasLayout.drawnHeight(of: widget("a", size: "auto", 0, 0, 200, 0), content: nil, grows: true), 40)
    }

    func testDraggingTheHeightBelowTheContentStoresTheDrawnHeight() {
        let start = BoardFrame(x: 24, y: 24, w: 336, h: 300)
        let result = CanvasLayout.resizedGrowing(
            start, width: 336, height: 120, content: 300, minimum: CanvasSize(w: 160, h: 40))
        XCTAssertEqual(result.frame, BoardFrame(x: 24, y: 24, w: 336, h: 120))
        XCTAssertFalse(result.auto)
    }

    func testDraggingPastTheContentStoresTheContentHeight() {
        let start = BoardFrame(x: 24, y: 24, w: 336, h: 100)
        let result = CanvasLayout.resizedGrowing(
            start, width: 336, height: 400, content: 220, minimum: CanvasSize(w: 160, h: 40))
        XCTAssertTrue(result.auto)
        XCTAssertEqual(result.frame.h, 220)
    }

    func testWithinOneSnapOfTheContentTurnsBackToAuto() {
        let start = BoardFrame(x: 24, y: 24, w: 336, h: 100)
        let minimum = CanvasSize(w: 160, h: 40)
        XCTAssertTrue(CanvasLayout.resizedGrowing(start, width: 336, height: 216, content: 220, minimum: minimum).auto)
        XCTAssertTrue(CanvasLayout.resizedGrowing(start, width: 336, height: 213, content: 220, minimum: minimum).auto)
        XCTAssertFalse(CanvasLayout.resizedGrowing(start, width: 336, height: 200, content: 220, minimum: minimum).auto)
    }

    func testTheResizeHeightNeverGoesUnderTheFloorAndWidthStaysSnapped() {
        let start = BoardFrame(x: 24, y: 24, w: 336, h: 200)
        let result = CanvasLayout.resizedGrowing(
            start, width: 333, height: 3, content: 500, minimum: CanvasSize(w: 160, h: 40))
        XCTAssertEqual(result.frame, BoardFrame(x: 24, y: 24, w: 336, h: 40))
    }

    func testAContentShorterThanTheFloorIsAlwaysAuto() {
        let start = BoardFrame(x: 24, y: 24, w: 336, h: 32)
        let result = CanvasLayout.resizedGrowing(
            start, width: 336, height: 5, content: 32, minimum: CanvasSize(w: 160, h: 40))
        XCTAssertTrue(result.auto)
        XCTAssertEqual(result.frame.h, 32)
    }

    func testAWidgetUnderAGrowingOneMovesDownOnScreenOnly() {
        let drawn = CanvasLayout.pushedDown([place("machines", 24, 24, 400, 300), place("usage", 24, 168, 400, 200)])
        XCTAssertEqual(drawn["machines"], 24)
        XCTAssertEqual(drawn["usage"], 24 + 300 + CanvasLayout.gap)
    }

    func testPushDownNeverPullsUp() {
        let drawn = CanvasLayout.pushedDown([place("machines", 24, 24, 400, 100), place("usage", 24, 400, 400, 200)])
        XCTAssertEqual(drawn["usage"], 400)
    }

    func testPushDownIgnoresWidgetsWhoseColumnsDoNotOverlap() {
        let drawn = CanvasLayout.pushedDown([place("machines", 24, 24, 400, 300), place("clock", 424, 168, 300, 100)])
        XCTAssertEqual(drawn["clock"], 168)
        let touching = CanvasLayout.pushedDown([place("a", 0, 0, 100, 300), place("b", 100, 100, 100, 50)])
        XCTAssertEqual(touching["b"], 100)
        let overlapping = CanvasLayout.pushedDown([place("a", 0, 0, 101, 300), place("b", 100, 100, 100, 50)])
        XCTAssertEqual(overlapping["b"], 308)
    }

    func testPushDownChainsThroughSeveralWidgets() {
        let drawn = CanvasLayout.pushedDown([
            place("a", 0, 0, 100, 200), place("b", 0, 100, 100, 100), place("c", 0, 200, 100, 100),
        ])
        XCTAssertEqual(drawn["a"], 0)
        XCTAssertEqual(drawn["b"], 208)
        XCTAssertEqual(drawn["c"], 316)
    }

    func testPushDownOrdersByStoredYThenXNotByListOrder() {
        let items = [place("low", 0, 300, 100, 50), place("high", 0, 0, 100, 400), place("left", 0, 300, 100, 50)]
        let drawn = CanvasLayout.pushedDown(items)
        XCTAssertEqual(drawn["high"], 0)
        XCTAssertEqual(drawn["low"], 408)
        XCTAssertEqual(drawn["left"], 466)
    }

    func testPushDownBreaksAYAndXTieByX() {
        let drawn = CanvasLayout.pushedDown([place("right", 50, 0, 100, 40), place("left", 0, 0, 100, 40)])
        XCTAssertEqual(drawn["left"], 0)
        XCTAssertEqual(drawn["right"], 48)
    }

    func testResetOfAGrowingWidgetIsAutoAtTheDefaultWidth() {
        let capped = widget("machines", 40, 60, 900, 220)
        let reset = CanvasLayout.reset(capped, defaultSize: "medium", grows: true)
        XCTAssertEqual(reset.size, "auto")
        XCTAssertEqual(reset.frame, BoardFrame(x: 40, y: 60, w: 320, h: 0))
        XCTAssertTrue(reset.isAuto)
        XCTAssertEqual(reset.id, "machines")
        XCTAssertEqual(reset.z, capped.z)
    }

    func testResetOfAFixedWidgetIsItsDefaultPreset() {
        let clock = widget("clock", 40, 60, 900, 220)
        let reset = CanvasLayout.reset(clock, defaultSize: "large", grows: false)
        XCTAssertEqual(reset.size, "large")
        XCTAssertEqual(reset.frame, BoardFrame(x: 40, y: 60, w: 320, h: 320))
    }

    func testTheCanvasPlacementOfAnAutoWidgetUsesTheDrawnHeight() {
        let placement = CanvasLayout.placement(
            of: widget("summary", size: "auto", 24, 24, 336, 0), content: 44, grows: true)
        XCTAssertEqual(placement, CanvasPlacement(id: "summary", x: 24, y: 24, w: 336, h: 44))
    }
}
