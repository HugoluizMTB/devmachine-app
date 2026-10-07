import XCTest
@testable import DevmachineCore

final class BoardCodecEditTests: XCTestCase {
    private let home = """
        format: 1
        surface: home
        widgets:
          - id: machines
            type: devmachine-app/machines
            title: Servers
            with: {machines: [main, here]}
            every: 2m
            frame: {x: 24, y: 24, w: 384, h: 320}
            size: custom
            minimized: false
            z: 1
          - id: usage
            type: devmachine-app/usage
            with: {harness: claude}
            frame: {x: 24, y: 360, w: 384, h: 288}
            size: custom
            minimized: false
            z: 2

        """

    private let sidebar = """
        format: 1
        surface: sidebar
        widgets:
          - id: machines
            type: devmachine-app/machines
            title: Servers
            with: {machines: []}
            every: manual
            size: auto

        """

    func testListsAndOverridesSurviveARewriteByteForByte() throws {
        let board = try BoardCodec.decode(home)
        XCTAssertEqual(board.widgets[0].with["machines"], .list(["main", "here"]))
        XCTAssertEqual(board.widgets[0].titleOverride, "Servers")
        XCTAssertEqual(board.widgets[0].everyOverride, "2m")
        XCTAssertNil(board.widgets[1].titleOverride)
        XCTAssertEqual(BoardCodec.encode(board), home)
        let stack = try BoardCodec.decodeStack(sidebar)
        XCTAssertEqual(stack.entries[0].with["machines"], .list([]))
        XCTAssertEqual(stack.entries[0].everyOverride, "manual")
        XCTAssertEqual(BoardCodec.encodeStack(stack), sidebar)
    }

    func testAListJoinsWithCommasForATemplate() {
        XCTAssertEqual(BoardScalar.list(["main", "here"]).text, "main,here")
        XCTAssertEqual(BoardScalar.list([]).text, "")
        XCTAssertEqual(BoardScalar.list(["a"]).listValue, ["a"])
        XCTAssertNil(BoardScalar.string("a").listValue)
    }

    func testAListItemThatIsNotTextIsRefusedAtItsLine() {
        let text = home.replacingOccurrences(of: "[main, here]", with: "[main, {a: b}]")
        XCTAssertThrowsError(try BoardCodec.decode(text)) { error in
            XCTAssertEqual(
                error as? BoardProblem,
                BoardProblem(line: 7, message: "machines: input \"machines\" takes a list of names, written [a, b]"))
        }
    }

    func testAnEmptyTitleIsRefused() {
        let text = home.replacingOccurrences(of: "title: Servers", with: "title: \"\"")
        XCTAssertThrowsError(try BoardCodec.decode(text)) { error in
            XCTAssertEqual(
                error as? BoardProblem,
                BoardProblem(line: 6, message: "machines: title is empty: write one, or take the key off to show the widget's own"))
        }
    }

    func testEveryMustBeADurationOrManual() {
        let text = home.replacingOccurrences(of: "every: 2m", with: "every: often")
        XCTAssertThrowsError(try BoardCodec.decode(text)) { error in
            XCTAssertEqual(
                error as? BoardProblem,
                BoardProblem(line: 8, message: "machines: every \"often\" is neither a duration nor manual: write it like 60s, 5m or manual"))
        }
    }

    func testAnInlineWidgetTakesNoEveryOverride() {
        let text = """
            format: 1
            surface: sidebar
            widgets:
              - id: disk
                title: Disk
                source: {kind: command, run: df, every: 60s}
                view: {kind: text}
                every: 5m

            """
        XCTAssertThrowsError(try BoardCodec.decodeStack(text)) { error in
            XCTAssertEqual(
                error as? BoardProblem,
                BoardProblem(line: 8, message: "disk: a widget written in the board sets how often in source.every, not every"))
        }
    }

    func testOverridesReachTheResolverThroughAStackEntry() throws {
        let entry = try BoardCodec.decodeStack(sidebar).entries[0]
        XCTAssertEqual(entry.boardWidget.titleOverride, "Servers")
        XCTAssertEqual(entry.boardWidget.everyOverride, "manual")
        XCTAssertEqual(entry.boardWidget.with, entry.with)
    }

    func testAListValueEncodesAsAJSONArray() throws {
        let data = try JSONEncoder().encode(BoardScalar.list(["main"]))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"main\"]")
        XCTAssertEqual(try JSONDecoder().decode(BoardScalar.self, from: data), .list(["main"]))
    }
}
