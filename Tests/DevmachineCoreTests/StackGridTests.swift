import XCTest
@testable import DevmachineCore

final class StackGridTests: XCTestCase {
    func testDimsForKnownCounts() {
        let cases: [(Int, Int, Int)] = [
            (1, 1, 1),
            (2, 2, 1),
            (3, 2, 2),
            (4, 2, 2),
            (5, 3, 2),
            (6, 3, 2),
            (9, 3, 3)
        ]
        for (n, cols, rows) in cases {
            let dims = StackGrid.dims(n)
            XCTAssertEqual(dims.cols, cols, "cols for n=\(n)")
            XCTAssertEqual(dims.rows, rows, "rows for n=\(n)")
        }
    }

    func testNextCyclesAutoHalfFull() {
        XCTAssertEqual(StackCellSize.auto.next, .half)
        XCTAssertEqual(StackCellSize.half.next, .full)
        XCTAssertEqual(StackCellSize.full.next, .auto)
    }

    func testLayoutTwoAutosSplitRowEvenly() {
        let rects = StackGrid.layout([.auto, .auto])
        XCTAssertEqual(rects.count, 2)
        assertRect(rects[0], index: 0, x: 0, y: 0, w: 0.5, h: 1.0)
        assertRect(rects[1], index: 1, x: 0.5, y: 0, w: 0.5, h: 1.0)
    }

    func testLayoutThreeAutosLoneCellFillsLastRow() {
        let rects = StackGrid.layout([.auto, .auto, .auto])
        XCTAssertEqual(rects.count, 3)
        assertRect(rects[0], index: 0, x: 0, y: 0, w: 0.5, h: 0.5)
        assertRect(rects[1], index: 1, x: 0.5, y: 0, w: 0.5, h: 0.5)
        assertRect(rects[2], index: 2, x: 0, y: 0.5, w: 1.0, h: 0.5)
    }

    func testLayoutFourAutosMakesTwoByTwo() {
        let rects = StackGrid.layout([.auto, .auto, .auto, .auto])
        XCTAssertEqual(rects.count, 4)
        assertRect(rects[0], index: 0, x: 0, y: 0, w: 0.5, h: 0.5)
        assertRect(rects[1], index: 1, x: 0.5, y: 0, w: 0.5, h: 0.5)
        assertRect(rects[2], index: 2, x: 0, y: 0.5, w: 0.5, h: 0.5)
        assertRect(rects[3], index: 3, x: 0.5, y: 0.5, w: 0.5, h: 0.5)
    }

    func testLayoutFiveAutosThreeColsSecondRowStretches() {
        let rects = StackGrid.layout(Array(repeating: .auto, count: 5))
        XCTAssertEqual(rects.count, 5)
        let third = 1.0 / 3.0
        assertRect(rects[0], index: 0, x: 0, y: 0, w: third, h: 0.5)
        assertRect(rects[1], index: 1, x: third, y: 0, w: third, h: 0.5)
        assertRect(rects[2], index: 2, x: 2 * third, y: 0, w: third, h: 0.5)
        assertRect(rects[3], index: 3, x: 0, y: 0.5, w: 0.5, h: 0.5)
        assertRect(rects[4], index: 4, x: 0.5, y: 0.5, w: 0.5, h: 0.5)
    }

    func testLayoutFullTakesOwnRow() {
        let rects = StackGrid.layout([.full, .auto, .auto])
        XCTAssertEqual(rects.count, 3)
        assertRect(rects[0], index: 0, x: 0, y: 0, w: 1.0, h: 0.5)
        assertRect(rects[1], index: 1, x: 0, y: 0.5, w: 0.5, h: 0.5)
        assertRect(rects[2], index: 2, x: 0.5, y: 0.5, w: 0.5, h: 0.5)
    }

    func testLayoutLoneHalfStaysHalfWidth() {
        let rects = StackGrid.layout([.half, .half, .half])
        XCTAssertEqual(rects.count, 3)
        assertRect(rects[0], index: 0, x: 0, y: 0, w: 0.5, h: 0.5)
        assertRect(rects[1], index: 1, x: 0.5, y: 0, w: 0.5, h: 0.5)
        assertRect(rects[2], index: 2, x: 0, y: 0.5, w: 0.5, h: 0.5)
    }

    private func assertRect(
        _ rect: StackCellRect,
        index: Int,
        x: Double,
        y: Double,
        w: Double,
        h: Double,
        line: UInt = #line
    ) {
        XCTAssertEqual(rect.index, index, "index", line: line)
        XCTAssertEqual(rect.x, x, accuracy: 1e-9, "x", line: line)
        XCTAssertEqual(rect.y, y, accuracy: 1e-9, "y", line: line)
        XCTAssertEqual(rect.width, w, accuracy: 1e-9, "width", line: line)
        XCTAssertEqual(rect.height, h, accuracy: 1e-9, "height", line: line)
    }
}
