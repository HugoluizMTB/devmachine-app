import XCTest
@testable import DevmachineCore

final class BoardCodecAutoTests: XCTestCase {
    private func board(frame: String, size: String? = nil, type: String = "devmachine-app/summary") -> String {
        var text = """
            format: 1
            surface: home
            widgets:
              - id: summary
                type: \(type)
                frame: \(frame)

            """
        if let size { text += "    size: \(size)\n" }
        return text
    }

    private func problem(_ text: String) -> BoardProblem? {
        do {
            _ = try BoardCodec.decode(text)
            return nil
        } catch let problem as BoardProblem {
            return problem
        } catch {
            XCTFail("unexpected \(error)")
            return nil
        }
    }

    func testAnAutoEntryHasNoHeight() throws {
        let decoded = try BoardCodec.decode(board(frame: "{x: 24, y: 40, w: 336}", size: "auto"))
        let widget = try XCTUnwrap(decoded.widgets.first)
        XCTAssertEqual(widget.size, "auto")
        XCTAssertTrue(widget.isAuto)
        XCTAssertEqual(widget.frame, BoardFrame(x: 24, y: 40, w: 336, h: 0))
    }

    func testAHeightNextToAutoIsIgnoredAndDroppedOnWrite() throws {
        let decoded = try BoardCodec.decode(board(frame: "{x: 24, y: 40, w: 336, h: 160}", size: "auto"))
        XCTAssertEqual(decoded.widgets.first?.frame.h, 0)
        XCTAssertEqual(BoardCodec.encode(decoded), """
            format: 1
            surface: home
            widgets:
              - id: summary
                type: devmachine-app/summary
                frame: {x: 24, y: 40, w: 336}
                size: auto
                minimized: false
                z: 0

            """)
    }

    func testAnAutoBoardRoundTripsByteForByte() throws {
        let text = """
            format: 1
            surface: home
            widgets:
              - id: summary
                type: devmachine-app/summary
                frame: {x: 24, y: 40, w: 336}
                size: auto
                minimized: false
                z: 1
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 400, w: 320, h: 160}
                size: medium
                minimized: false
                z: 2

            """
        XCTAssertEqual(BoardCodec.encode(try BoardCodec.decode(text)), text)
    }

    func testWithoutAutoTheFrameNeedsAHeight() {
        XCTAssertEqual(
            problem(board(frame: "{x: 24, y: 40, w: 336}", size: "custom")),
            BoardProblem(line: 4, message: "summary: frame needs h unless size is auto"))
        XCTAssertEqual(
            problem(board(frame: "{x: 24, y: 40, w: 336}")),
            BoardProblem(line: 4, message: "summary: frame needs h unless size is auto"))
        XCTAssertEqual(
            problem(board(frame: "{x: 24, y: 40, w: 336}", size: "medium")),
            BoardProblem(line: 4, message: "summary: frame needs h unless size is auto"))
    }

    func testAHeightOfZeroIsStillRefusedWithoutAuto() {
        XCTAssertEqual(
            problem(board(frame: "{x: 24, y: 40, w: 336, h: 0}", size: "custom")),
            BoardProblem(line: 6, message: "frame.h of widget \"summary\" must be more than 0"))
    }

    func testAnUnknownSizeNamesThePresetsCustomAndAuto() {
        XCTAssertEqual(
            problem(board(frame: "{x: 24, y: 40, w: 336, h: 160}", size: "huge")),
            BoardProblem(
                line: 7,
                message: "summary: size \"huge\" is a preset (small, medium, tall, large, wide), custom or auto"))
    }

    func testAnInlineViewThatDoesNotGrowRefusesAuto() {
        let text = """
            format: 1
            surface: home
            widgets:
              - id: dial
                title: Dial
                source: {kind: command, run: uptime, target: local, every: 60s, parse: number}
                view: {kind: gauge}
                frame: {x: 24, y: 40, w: 336}
                size: auto
            """
        XCTAssertEqual(problem(text)?.line, 9)
        XCTAssertEqual(
            problem(text)?.message,
            "dial: size auto follows the content, and the gauge view does not grow: use small, medium, tall, large, wide")
    }

    func testAnInlineViewThatGrowsTakesAuto() throws {
        let text = """
            format: 1
            surface: home
            widgets:
              - id: disk
                title: Disk
                source: {kind: command, run: uptime, target: local, every: 60s, parse: text}
                view: {kind: text}
                frame: {x: 24, y: 40, w: 336}
                size: auto
            """
        let decoded = try BoardCodec.decode(text)
        XCTAssertTrue(decoded.widgets[0].isAuto)
        XCTAssertTrue(BoardCodec.encode(decoded).contains("    frame: {x: 24, y: 40, w: 336}\n    size: auto\n"))
    }
}
