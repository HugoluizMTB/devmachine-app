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

    func testOutOfRangePaletteEntriesAreIgnored() {
        let runs = ANSIText.lines("\u{1B}[31ma\u{1B}[38;5;99999mb\u{1B}[38;5;-3mc\u{1B}[48;5;999;1md")[0]
        XCTAssertEqual(runs, [
            ANSIRun(text: "abc", foreground: .palette(1)),
            ANSIRun(text: "d", foreground: .palette(1), bold: true),
        ])
    }

    func testShortTrueColorSkipsTheRestOfTheSequence() {
        let runs = ANSIText.lines("\u{1B}[38;2;1;2mx")[0]
        XCTAssertEqual(runs, [ANSIRun(text: "x")])
    }

    func testAnUnreadableCodeIsSkippedNotAReset() {
        let runs = ANSIText.lines("\u{1B}[1mA\u{1B}[?;31mB")[0]
        XCTAssertEqual(runs, [
            ANSIRun(text: "A", bold: true),
            ANSIRun(text: "B", foreground: .palette(1), bold: true),
        ])
    }

    func testUnterminatedEscapesDropTheRestOfTheLine() {
        XCTAssertEqual(ANSIText.lines("ok\u{1B}[31").first?.map(\.text).joined(), "ok")
        XCTAssertEqual(ANSIText.lines("ok\u{1B}]0;title").first?.map(\.text).joined(), "ok")
        XCTAssertEqual(ANSIText.lines("ok\u{1B}").first?.map(\.text).joined(), "ok")
    }

    func testCSIEndsOnlyOnAFinalByte() {
        XCTAssertEqual(ANSIText.lines("\u{1B}[1é;31mz").first?.map(\.text).joined(), "z")
    }

    func testAnOSCEndedByAnotherEscapeKeepsThatEscape() {
        let runs = ANSIText.lines("\u{1B}]0;title\u{1B}[31mred")[0]
        XCTAssertEqual(runs, [ANSIRun(text: "red", foreground: .palette(1))])
    }

    func testAMegabyteOfStylesFinishesBounded() {
        let chunk = "\u{1B}[31ma\u{1B}[32mb"
        let text = String(repeating: chunk, count: 1_048_576 / chunk.utf8.count)
        let lines = ANSIText.lines(text)
        XCTAssertEqual(lines.count, 1)
        XCTAssertLessThanOrEqual(lines[0].count, text.utf8.count)
        XCTAssertEqual(lines[0].map(\.text).joined().count, 2 * (1_048_576 / chunk.utf8.count))
    }
}
