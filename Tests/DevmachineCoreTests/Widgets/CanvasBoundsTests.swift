import XCTest
@testable import DevmachineCore

final class CanvasBoundsTests: XCTestCase {
    private let canvas = CGSize(width: 1000, height: 700)

    private func frame(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> BoardFrame { BoardFrame(x: x, y: y, w: w, h: h) }

    private func assertGrabbable(_ shown: BoardFrame, in canvas: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        let grab = CGRect(
            x: Double(shown.x), y: Double(shown.y),
            width: Double(min(shown.w, CanvasBounds.grab.w)), height: Double(min(shown.h, CanvasBounds.grab.h)))
        XCTAssertGreaterThan(shown.w, 0, file: file, line: line)
        XCTAssertGreaterThan(shown.h, 0, file: file, line: line)
        XCTAssertTrue(CGRect(origin: .zero, size: canvas).contains(grab), "\(shown)", file: file, line: line)
    }

    func testAFrameThatFitsIsUnchanged() {
        let fits = frame(24, 24, 320, 160)
        XCTAssertEqual(CanvasBounds.onCanvas(fits, in: canvas), fits)
        XCTAssertEqual(CanvasBounds.onCanvas(frame(680, 540, 320, 160), in: canvas), frame(680, 540, 320, 160))
    }

    func testAFrameDraggedPastEachEdgeEndsFullyVisible() {
        XCTAssertEqual(CanvasBounds.onCanvas(frame(1400, 100, 320, 160), in: canvas), frame(680, 100, 320, 160))
        XCTAssertEqual(CanvasBounds.onCanvas(frame(100, 2000, 320, 160), in: canvas), frame(100, 540, 320, 160))
        XCTAssertEqual(CanvasBounds.onCanvas(frame(-500, 100, 320, 160), in: canvas), frame(0, 100, 320, 160))
        XCTAssertEqual(CanvasBounds.onCanvas(frame(100, -500, 320, 160), in: canvas), frame(100, 0, 320, 160))
        XCTAssertEqual(CanvasBounds.onCanvas(frame(5000, 5000, 320, 160), in: canvas), frame(680, 540, 320, 160))
    }

    func testAFrameBiggerThanTheCanvasKeepsItsTopLeftOnScreen() {
        let shown = CanvasBounds.onCanvas(frame(300, 300, 1600, 900), in: canvas)
        XCTAssertEqual(shown, frame(0, 0, 1600, 900))
        assertGrabbable(shown, in: canvas)
    }

    func testAFrameNeverHasAZeroOrNegativeSize() {
        let shown = CanvasBounds.onCanvas(frame(990, 690, 0, -20), in: canvas)
        XCTAssertGreaterThan(shown.w, 0)
        XCTAssertGreaterThan(shown.h, 0)
        assertGrabbable(shown, in: canvas)
    }

    func testAFrameLoadedFarOffTheCanvasComesBackIntoView() {
        for stored in [frame(9000, 40, 320, 160), frame(40, 9000, 160, 160), frame(9000, 9000, 640, 320)] {
            let shown = CanvasBounds.onCanvas(stored, in: canvas)
            XCTAssertTrue(CGRect(origin: .zero, size: canvas).contains(shown.rect), "\(stored)")
        }
    }

    func testAnEmptyCanvasPinsEveryFrameToTheOrigin() {
        XCTAssertEqual(CanvasBounds.onCanvas(frame(400, 300, 320, 160), in: .zero), frame(0, 0, 320, 160))
    }

    func testTheMinimumRaisesADeclaredSizeToTheFloor() {
        XCTAssertEqual(CanvasBounds.minimum(declared: CanvasSize(w: 320, h: 320), grows: false), CanvasSize(w: 320, h: 320))
        XCTAssertEqual(CanvasBounds.minimum(declared: CanvasSize(w: 1, h: 1), grows: false), CanvasBounds.floor)
        XCTAssertEqual(CanvasBounds.minimum(declared: nil, grows: false), CanvasBounds.floor)
    }

    func testAGrowingViewIsFlooredOnlyToTheGrabHeight() {
        let minimum = CanvasBounds.minimum(declared: CanvasSize(w: 160, h: 40), grows: true)
        XCTAssertEqual(minimum, CanvasSize(w: 160, h: CanvasBounds.grab.h))
    }

    func testTheFloorIsLargerThanTheGrabArea() {
        XCTAssertGreaterThanOrEqual(CanvasBounds.floor.w, CanvasBounds.grab.w)
        XCTAssertGreaterThanOrEqual(CanvasBounds.floor.h, CanvasBounds.grab.h)
        XCTAssertGreaterThanOrEqual(CanvasBounds.grab.h, 44)
        XCTAssertGreaterThanOrEqual(CanvasBounds.grab.w, 120)
    }

    func testAResizeToATinyOrNegativeSizeStopsAtTheMinimum() {
        let start = frame(24, 24, 320, 160)
        let minimum = CanvasBounds.minimum(declared: nil, grows: false)
        let tiny = CanvasBounds.fitted(CanvasLayout.resized(start, width: 3, height: 2, minimum: minimum), minimum: minimum, in: canvas)
        XCTAssertEqual(tiny, frame(24, 24, 160, 80))
        let negative = CanvasBounds.fitted(
            CanvasLayout.resized(start, width: -400, height: -90, minimum: minimum), minimum: minimum, in: canvas)
        XCTAssertEqual(negative, frame(24, 24, 160, 80))
    }

    func testAnErrorWidgetResizedSmallKeepsTheFloor() {
        let minimum = CanvasBounds.minimum(declared: nil, grows: false)
        let resized = CanvasLayout.resized(frame(0, 0, 160, 160), width: 8, height: 8, minimum: minimum)
        XCTAssertEqual(CanvasSize(w: resized.w, h: resized.h), CanvasBounds.floor)
    }

    func testAGrowingResizeNeverDrawsUnderTheGrabHeight() {
        let minimum = CanvasBounds.minimum(declared: CanvasSize(w: 160, h: 40), grows: true)
        let result = CanvasLayout.resizedGrowing(frame(0, 0, 320, 200), width: 10, height: 0, content: 300, minimum: minimum)
        XCTAssertEqual(result.frame.w, 160)
        XCTAssertEqual(result.frame.h, CanvasBounds.grab.h)
    }

    func testAResizePastTheCanvasEdgeStopsAtTheEdge() {
        let minimum = CanvasBounds.minimum(declared: CanvasSize(w: 160, h: 160), grows: false)
        let shown = CanvasBounds.fitted(frame(600, 400, 900, 900), minimum: minimum, in: canvas)
        XCTAssertEqual(shown, frame(600, 400, 400, 300))
    }

    func testAResizeThatCannotFitTheMinimumMovesTheWidgetIn() {
        let minimum = CanvasBounds.minimum(declared: CanvasSize(w: 320, h: 320), grows: false)
        let shown = CanvasBounds.fitted(frame(900, 600, 320, 320), minimum: minimum, in: canvas)
        XCTAssertEqual(shown, frame(680, 380, 320, 320))
    }

    func testAResizeThatKeepsItsHeightOnlyCapsTheWidth() {
        let minimum = CanvasBounds.minimum(declared: CanvasSize(w: 160, h: 40), grows: true)
        let shown = CanvasBounds.fitted(frame(600, 100, 900, 2000), minimum: minimum, in: canvas, capsHeight: false)
        XCTAssertEqual(shown.w, 400)
        XCTAssertEqual(shown.h, 2000)
    }

    func testAWidgetPushedDownPastTheBottomKeepsItsGrabStripOnScreen() {
        let frames = ["top": frame(0, 0, 320, 680), "below": frame(0, 100, 320, 160)]
        let shown = CanvasBounds.settled(frames, in: canvas, holding: nil)
        XCTAssertEqual(shown["top"], frame(0, 0, 320, 680))
        XCTAssertEqual(shown["below"]?.y, 700 - CanvasBounds.grab.h)
        assertGrabbable(shown["below"]!, in: canvas)
    }

    func testPushDownStillSpacesWidgetsThatFit() {
        let frames = ["top": frame(0, 0, 320, 200), "below": frame(0, 100, 320, 160)]
        let shown = CanvasBounds.settled(frames, in: canvas, holding: nil)
        XCTAssertEqual(shown["below"]?.y, 200 + CanvasLayout.gap)
    }

    func testTheHeldWidgetIsNeitherPushedNorMoved() {
        let frames = ["top": frame(0, 0, 320, 200), "held": frame(0, 100, 320, 160)]
        XCTAssertEqual(CanvasBounds.settled(frames, in: canvas, holding: "held")["held"], frame(0, 100, 320, 160))
    }

    func testEveryWidgetStaysGrabbableWhenTheCanvasShrinks() {
        let stored = [
            "a": frame(24, 24, 640, 320), "b": frame(700, 24, 320, 160), "c": frame(24, 400, 960, 400),
            "d": frame(1200, 900, 160, 160),
        ]
        let small = CGSize(width: 480, height: 360)
        let shown = CanvasBounds.settled(stored.mapValues { CanvasBounds.onCanvas($0, in: small) }, in: small, holding: nil)
        XCTAssertEqual(Set(shown.keys), Set(stored.keys))
        for frame in shown.values { assertGrabbable(frame, in: small) }
    }

    func testClampingNeverRewritesTheStoredLayout() {
        let stored = ["a": frame(24, 24, 320, 160), "b": frame(900, 600, 320, 160)]
        let small = CGSize(width: 600, height: 400)
        let shrunk = CanvasBounds.settled(stored.mapValues { CanvasBounds.onCanvas($0, in: small) }, in: small, holding: nil)
        XCTAssertNotEqual(shrunk["b"], stored["b"])
        let big = CGSize(width: 1400, height: 900)
        let grown = CanvasBounds.settled(stored.mapValues { CanvasBounds.onCanvas($0, in: big) }, in: big, holding: nil)
        XCTAssertEqual(grown, stored)
    }
}
