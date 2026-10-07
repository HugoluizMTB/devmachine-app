import XCTest
@testable import DevmachineCore

final class BoardCodecTests: XCTestCase {
    private let specExample = """
        format: 1
        surface: home
        widgets:
          - id: clock                    # unique in the board
            type: devmachine-app/clock
            with: {}
            frame: {x: 24, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 1
        """

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

    func testDecodesTheSpecExample() throws {
        let board = try BoardCodec.decode(specExample)
        XCTAssertEqual(board.surface, "home")
        XCTAssertEqual(board.widgets, [
            BoardWidget(
                id: "clock", type: "devmachine-app/clock",
                frame: BoardFrame(x: 24, y: 24, w: 320, h: 160), size: "medium", z: 1),
        ])
    }

    func testEncodesInTheWritersKeyOrder() {
        let board = Board(surface: "home", widgets: [
            BoardWidget(
                id: "clock", type: "devmachine-app/clock",
                frame: BoardFrame(x: 24, y: 24, w: 320, h: 160), size: "medium", z: 1),
            BoardWidget(
                id: "claude-usage", type: "claude-code/usage", with: ["harness": .string("claude")],
                frame: BoardFrame(x: 24, y: 360, w: 320, h: 160), size: "custom", minimized: true, z: 4),
        ])
        XCTAssertEqual(BoardCodec.encode(board), """
            format: 1
            surface: home
            widgets:
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 24, w: 320, h: 160}
                size: medium
                minimized: false
                z: 1
              - id: claude-usage
                type: claude-code/usage
                with: {harness: claude}
                frame: {x: 24, y: 360, w: 320, h: 160}
                size: custom
                minimized: true
                z: 4

            """)
    }

    func testAnEmptyBoardWritesAnEmptyList() throws {
        let text = BoardCodec.encode(Board(surface: "home", widgets: []))
        XCTAssertEqual(text, "format: 1\nsurface: home\nwidgets: []\n")
        XCTAssertEqual(try BoardCodec.decode(text), Board(surface: "home", widgets: []))
    }

    func testRoundTripKeepsEveryScalarKind() throws {
        let board = Board(surface: "home", widgets: [
            BoardWidget(
                id: "w1", type: "acme/widget",
                with: ["a": .string("text"), "b": .int(42), "c": .double(1.5), "d": .bool(true)],
                frame: BoardFrame(x: 0, y: 8, w: 160, h: 160), size: "small", minimized: true, z: -2),
        ])
        XCTAssertEqual(try BoardCodec.decode(BoardCodec.encode(board)), board)
    }

    func testOptionalFieldsTakeTheirDefaults() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 24, w: 320, h: 160}
            """)
        XCTAssertEqual(board.widgets.first?.size, BoardWidget.customSize)
        XCTAssertEqual(board.widgets.first?.minimized, false)
        XCTAssertEqual(board.widgets.first?.z, 0)
        XCTAssertEqual(board.widgets.first?.with, [:])
    }

    func testReadsBlockStyleCommentsAndQuotes() throws {
        let board = try BoardCodec.decode("""
            # written by hand
            format: 1
            surface: "home"
            widgets:
              - id: 'usage'
                type: "claude-code/usage"
                with:
                  harness: claude   # the harness id
                frame:
                  x: 24
                  y: 360
                  w: 320
                  h: 160
                z: 3
            """)
        XCTAssertEqual(board.widgets.first?.id, "usage")
        XCTAssertEqual(board.widgets.first?.with, ["harness": .string("claude")])
        XCTAssertEqual(board.widgets.first?.frame, BoardFrame(x: 24, y: 360, w: 320, h: 160))
    }

    func testTextThatLooksLikeYAMLIsQuotedOnWrite() throws {
        let values: [String: BoardScalar] = [
            "a": .string("true"), "b": .string("8080"), "c": .string("a, b"),
            "d": .string("x: y"), "e": .string("say \"hi\""), "f": .string(""),
        ]
        let board = Board(surface: "home", widgets: [
            BoardWidget(
                id: "w", type: "acme/widget", with: values,
                frame: BoardFrame(x: 0, y: 0, w: 160, h: 160), size: "small", z: 1),
        ])
        XCTAssertEqual(try BoardCodec.decode(BoardCodec.encode(board)).widgets.first?.with, values)
    }

    func testAQuotedNumberStaysText() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: w
                type: acme/widget
                with: {port: "8080", count: 3}
                frame: {x: 0, y: 0, w: 160, h: 160}
            """)
        XCTAssertEqual(board.widgets.first?.with, ["port": .string("8080"), "count": .int(3)])
    }

    func testADuplicateIDNamesItsLine() {
        let found = problem("""
            format: 1
            surface: home
            widgets:
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 24, w: 320, h: 160}
              - id: summary
                type: devmachine-app/summary
                frame: {x: 368, y: 200, w: 640, h: 160}
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 24, w: 320, h: 160}
            """)
        XCTAssertEqual(found, BoardProblem(line: 10, message: "id \"clock\" is used twice"))
    }

    func testAnUnknownKeyNamesItsLine() {
        let found = problem("""
            format: 1
            surface: home
            widgets:
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 24, w: 320, h: 160}
                minimised: true
            """)
        XCTAssertEqual(found, BoardProblem(line: 7, message: "unknown key \"minimised\" in a widget"))
    }

    func testReadsAndRewritesTheCLIWritersBytes() throws {
        let cliBytes = """
            format: 1
            surface: home
            widgets:
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 24, w: 320, h: 160}
                size: medium
                minimized: false
                z: 1
              - id: ssh-status
                type: ssh_hardening/status
                with: {host: example.com, label: 'a, b', port: "8080", ratio: 1.5, retries: 3, strict: true}
                frame: {x: 352, y: 24, w: 320, h: 160}
                size: custom
                minimized: true
                z: 2

            """
        let board = try BoardCodec.decode(cliBytes)
        XCTAssertEqual(board.widgets.last?.type, "ssh_hardening/status")
        XCTAssertEqual(board.widgets.last?.with, [
            "host": .string("example.com"), "label": .string("a, b"), "port": .string("8080"),
            "ratio": .double(1.5), "retries": .int(3), "strict": .bool(true),
        ])
        XCTAssertEqual(BoardCodec.encode(board), cliBytes)
    }

    func testQuotesInputsTheWayTheCLIWriterDoes() throws {
        let cliBytes = #"""
            format: 1
            surface: home
            widgets:
              - id: w
                type: ssh_hardening/status
                with: {' q': ' lead', a: "yes", b: "1:20", c: "0x1F", d: "", e: "line one\nline two", f: it's, g: -x, h: 'x #y', i: café, j: "2026-10-06", k: "1_000", l: say "hi", m: ".5", n: "~", p: "tab\there", r: "null", s: 'a:b', t: '@x', u: '?x', v: 'x: y', w: '-', x: 1e+06, y: 1, z: 0.0001}
                frame: {x: 352, y: 24, w: 320, h: 160}
                size: custom
                minimized: false
                z: 2
              - id: keys
                type: acme/widget
                with: {"": 3, "8080": 2, 'a, b': 4, yes: 1}
                frame: {x: 0, y: 0, w: 160, h: 160}
                size: small
                minimized: false
                z: 3

            """#
        let board = try BoardCodec.decode(cliBytes)
        XCTAssertEqual(board.widgets.first?.with["a"], .string("yes"))
        XCTAssertEqual(board.widgets.first?.with["x"], .double(1_000_000))
        XCTAssertEqual(board.widgets.first?.with["e"], .string("line one\nline two"))
        XCTAssertEqual(BoardCodec.encode(board), cliBytes)
    }

    func testAPackageNameMayHoldAnUnderscoreButAWidgetNameMayNot() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: w
                type: ssh_hardening/status
                frame: {x: 0, y: 0, w: 160, h: 160}
            """)
        XCTAssertEqual(board.widgets.first?.type, "ssh_hardening/status")
        XCTAssertEqual(
            problem("""
                format: 1
                surface: home
                widgets:
                  - id: w
                    type: ssh_hardening/disk_usage
                    frame: {x: 0, y: 0, w: 160, h: 160}
                """),
            BoardProblem(line: 5, message: "type \"ssh_hardening/disk_usage\" must be <package>/<widget>"))
    }

    func testARepeatedInputNamesItsLine() {
        let found = problem("""
            format: 1
            surface: home
            widgets:
              - id: w
                type: acme/widget
                with:
                  port: 8080
                  port: 9090
                frame: {x: 0, y: 0, w: 160, h: 160}
            """)
        XCTAssertEqual(found, BoardProblem(line: 8, message: "\"port\" appears twice"))
    }

    func testAWidgetWrittenInPlaceNeedsEngine11() {
        let found = problem("""
            format: 1
            surface: home
            widgets:
              - id: disk
                source: {kind: command, run: df -h}
                view: {kind: text}
                frame: {x: 24, y: 24, w: 320, h: 160}
            """)
        XCTAssertEqual(found?.line, 4)
        XCTAssertEqual(
            found?.message,
            "a widget written in place (source and view, no type) needs engine 1.1; this app implements engine 1.1")
    }

    func testFrameValuesArePlainNonNegativeIntegers() {
        let negative = problem("""
            format: 1
            surface: home
            widgets:
              - id: w
                type: acme/widget
                frame: {x: -8, y: 0, w: 160, h: 160}
            """)
        XCTAssertEqual(negative, BoardProblem(line: 6, message: "frame.x of widget \"w\" must be 0 or more"))
        let quoted = problem("""
            format: 1
            surface: home
            widgets:
              - id: w
                type: acme/widget
                frame: {x: "24", y: 0, w: 160, h: 160}
            """)
        XCTAssertEqual(quoted, BoardProblem(line: 6, message: "frame.x of widget \"w\" must be a whole number"))
        let empty = problem("""
            format: 1
            surface: home
            widgets:
              - id: w
                type: acme/widget
                frame: {x: 0, y: 0, w: 0, h: 160}
            """)
        XCTAssertEqual(empty, BoardProblem(line: 6, message: "frame.w of widget \"w\" must be more than 0"))
    }

    func testFormatAndSurfaceAreChecked() {
        XCTAssertEqual(
            problem("format: 2\nsurface: home\nwidgets: []\n"),
            BoardProblem(line: 1, message: "format must be 1"))
        XCTAssertEqual(
            problem("format: 1\nsurface: kitchen\nwidgets: []\n"),
            BoardProblem(line: 2, message: "unknown surface \"kitchen\"; known: context-sidebar, home, sidebar"))
        XCTAssertEqual(
            problem("format: 1\nsurface: home\n"),
            BoardProblem(line: 1, message: "widgets is missing; use widgets: [] for an empty board"))
        XCTAssertEqual(problem("")?.line, 1)
    }

    func testBrokenYAMLNamesALine() {
        let found = problem("""
            format: 1
            surface: home
            widgets:
              - id: clock
                type: devmachine-app/clock
                frame: {x: 24, y: 24, w: 320, h: 160
              - id: summary
            """)
        XCTAssertNotNil(found?.line)
        XCTAssertTrue(found?.message.hasPrefix("not valid YAML: ") ?? false, found?.message ?? "")
    }

    func testUniqueIDsAvoidTakenOnes() {
        let board = Board(surface: "home", widgets: [
            BoardWidget(id: "clock", type: "devmachine-app/clock", frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "custom", z: 1),
            BoardWidget(id: "clock-2", type: "devmachine-app/clock", frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "custom", z: 2),
        ])
        XCTAssertEqual(board.uniqueID(base: "clock"), "clock-3")
        XCTAssertEqual(board.uniqueID(base: "claude-code-usage"), "claude-code-usage")
        XCTAssertEqual(board.uniqueID(base: "Weird Name!"), "weird-name")
        XCTAssertEqual(board.topZ, 2)
    }
}
