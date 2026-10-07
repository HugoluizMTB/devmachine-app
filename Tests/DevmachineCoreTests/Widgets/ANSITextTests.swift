import XCTest
@testable import DevmachineCore

final class ANSITextTests: XCTestCase {
    func testColorsAndReset() {
        let lines = ANSIText.lines("\u{1B}[1;31mred\u{1B}[0m plain")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0], [
            ANSIRun(text: "red", foreground: .palette(1), bold: true),
            ANSIRun(text: " plain"),
        ])
    }

    func testBrightTwoFiftySixAndTrueColor() {
        let runs = ANSIText.lines("\u{1B}[92ma\u{1B}[38;5;208mb\u{1B}[48;2;1;2;3mc")[0]
        XCTAssertEqual(runs.map(\.foreground), [.palette(10), .palette(208), .palette(208)])
        XCTAssertEqual(runs.last?.background, .rgb(1, 2, 3))
    }

    func testOtherEscapesAreDroppedAndLinesSplit() {
        let lines = ANSIText.lines("\u{1B}[2J\u{1B}]0;title\u{07}one\ntwo\r\n")
        XCTAssertEqual(lines.map { $0.map(\.text).joined() }, ["one", "two"])
    }

    func testCarriageReturnKeepsTheLastRedraw() {
        XCTAssertEqual(ANSIText.lines("10%\r50%\r100%")[0].map(\.text).joined(), "100%")
    }
}
