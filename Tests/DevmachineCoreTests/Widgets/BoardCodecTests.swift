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

    private let cliInlineBoard = """
        format: 1
        surface: home
        widgets:
          - id: disk
            title: Disk on alice
            source:
              kind: command
              run: df
              args: [-h, /]
              target: {workspace: alice}
              every: 60s
            view: {kind: text, tail: 20}
            sizes: [medium, wide]
            frame: {x: 24, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 1
          - id: clock
            type: devmachine-app/clock
            frame: {x: 352, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 2

        """

    private let cliBlockStyleBoard = """
        format: 1
        surface: home
        widgets:
          - id: disk
            title: 'Disk: alice'
            source:
              kind: command
              run: df
              args:
                - -h
                - 'x; y'
              every: 60s
              parse: lines
            view:
              kind: list
              item: {title: "{{item}}"}
            frame: {x: 24, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 1

        """

    private let handWrittenMixedBoard = """
        format: 1
        surface: home
        widgets:
          - id: probe
            title: "Probe #1"
            source:
              kind: url
              url: "https://example.com/health?a=1"
              every: 30s
              parse: json
            view:
              kind: list
              item:
                title: "{{item.name}}"
                subtitle: 'state: {{item.state}}'
                link: "{{item.url}}"
            sizes: [wide, large]
            fits: [canvas]
            frame: {x: 0, y: 0, w: 664, h: 160}
            size: wide
            minimized: true
            z: 3
          - id: tabs
            title: Tabs
            source: {kind: command, run: printf, args: ["a\\tb", '', "x"], parse: text, every: manual}
            view:
              kind: text
            frame: {x: 0, y: 200, w: 320, h: 160}

        """

    private let cliRewriteOfMixedBoard = """
        format: 1
        surface: home
        widgets:
          - id: probe
            title: 'Probe #1'
            source:
              kind: url
              url: "https://example.com/health?a=1"
              every: 30s
              parse: json
            view:
              kind: list
              item:
                title: "{{item.name}}"
                subtitle: 'state: {{item.state}}'
                link: "{{item.url}}"
            sizes: [wide, large]
            fits: [canvas]
            frame: {x: 0, y: 0, w: 664, h: 160}
            size: wide
            minimized: true
            z: 3
          - id: tabs
            title: Tabs
            source: {kind: command, run: printf, args: ["a\\tb", '', "x"], parse: text, every: manual}
            view:
              kind: text
            frame: {x: 0, y: 200, w: 320, h: 160}
            size: custom
            minimized: false
            z: 0

        """

    func testAnInlineWidgetSurvivesARewriteByteForByte() throws {
        XCTAssertEqual(BoardCodec.encode(try BoardCodec.decode(cliInlineBoard)), cliInlineBoard)
        XCTAssertEqual(BoardCodec.encode(try BoardCodec.decode(cliBlockStyleBoard)), cliBlockStyleBoard)
    }

    func testACRLFBoardKeepsItsFlowStyleAndRefusesAnchors() throws {
        let crlf = cliInlineBoard.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(BoardCodec.encode(try BoardCodec.decode(crlf)), cliInlineBoard)
        let anchored = crlf.replacingOccurrences(of: "args: [-h, /]", with: "args: &args [-h, /]")
        XCTAssertEqual(problem(anchored)?.line, 9)
    }

    func testARepeatedKeyInsideASourceIsAProblem() {
        let repeated = cliInlineBoard.replacingOccurrences(of: "      run: df\n", with: "      run: df\n      run: du\n")
        XCTAssertEqual(problem(repeated)?.line, 9)
    }

    func testAPlainTrueIsASwitchAsInTheCLI() throws {
        let board = cliInlineBoard.replacingOccurrences(of: "      run: df\n      args: [-h, /]\n", with: "      run: df -h /\n      shell: True\n")
        guard case let .command(command)? = try BoardCodec.decode(board).widgets.first?.inline?.source else { return XCTFail() }
        XCTAssertTrue(command.shell)
    }

    func testRewritesAHandWrittenBoardToTheCLIWritersBytes() throws {
        XCTAssertEqual(BoardCodec.encode(try BoardCodec.decode(handWrittenMixedBoard)), cliRewriteOfMixedBoard)
    }

    func testLongLinesStayOnOneLineAsTheCLIWritesThem() throws {
        let board = """
            format: 1
            surface: home
            widgets:
              - id: ask
                title: A rather long title for a widget that keeps going well past eighty columns of text
                source:
                  kind: prompt
                  harness: claude
                  prompt: "Summarize the open pull requests of acme and say which ones need my review today please"
                  target: local
                view: {kind: markdown}
                frame: {x: 24, y: 24, w: 320, h: 160}
                size: custom
                minimized: false
                z: 0

            """
        XCTAssertEqual(BoardCodec.encode(try BoardCodec.decode(board)), board)
    }

    func testTheTitleIsQuotedTheWayTheCLIQuotesIt() throws {
        let doubleQuoted = cliBlockStyleBoard.replacingOccurrences(of: "title: 'Disk: alice'", with: "title: \"Disk: alice\"")
        XCTAssertEqual(BoardCodec.encode(try BoardCodec.decode(doubleQuoted)), cliBlockStyleBoard)
    }

    func testAnInlineWidgetIsRead() throws {
        let board = try BoardCodec.decode(cliInlineBoard)
        let disk = try XCTUnwrap(board.widgets.first)
        XCTAssertTrue(disk.isInline)
        XCTAssertEqual(disk.type, "")
        XCTAssertEqual(disk.inline?.title, "Disk on alice")
        XCTAssertEqual(disk.inline?.sizes, ["medium", "wide"])
        XCTAssertEqual(disk.inline?.view.tail, 20)
        guard case let .command(command)? = disk.inline?.source else { return XCTFail() }
        XCTAssertEqual(command.target, .workspace("alice"))
        XCTAssertEqual(command.every, .interval(60))
    }

    func testAMoveKeepsTheInlineSourceAsWritten() throws {
        var board = try BoardCodec.decode(cliBlockStyleBoard)
        board.widgets[0].frame = BoardFrame(x: 48, y: 24, w: 320, h: 160)
        XCTAssertEqual(
            BoardCodec.encode(board),
            cliBlockStyleBoard.replacingOccurrences(of: "frame: {x: 24,", with: "frame: {x: 48,"))
    }

    func testInlineRulesNameTheirLine() {
        let cases: [(String, String, String, Int, String)] = [
            ("title missing", "    title: Disk on alice\n", "", 4, "widget \"disk\" written in the board needs a title"),
            ("view missing", "    view: {kind: text, tail: 20}\n", "", 4, "needs both a source and a view"),
            ("inputs given", "    title: Disk on alice\n", "    title: Disk on alice\n    with: {path: /}\n", 6,
             "widget \"disk\" written in the board has no inputs, so it takes no with"),
            ("type and source", "    title: Disk on alice\n", "    type: devmachine-app/clock\n", 4,
             "has either a type or a source and a view, not both"),
            ("every too fast", "every: 60s", "every: 1s", 11, "source.every 1s is below the command minimum of 5s"),
            ("relative script", "      run: df\n      args: [-h, /]\n", "      script: bin/df\n", 8,
             "a widget written in a board names an absolute path on the target"),
            ("an input template", "args: [-h, /]", "args: [-h, \"{{inputs.path}}\"]", 9, "has no inputs"),
            ("a view that does not take it", "view: {kind: text, tail: 20}", "view: {kind: gauge}", 12,
             "view.kind \"gauge\" takes number, json, and this command source gives text"),
            ("a view field", "tail: 20", "tail: 9000", 12, "view.tail 9000 is outside 1 to 2000 lines"),
            ("an unknown size", "sizes: [medium, wide]", "sizes: [medium, huge]", 13, "size \"huge\""),
            ("an unknown layout", "    sizes: [medium, wide]\n", "    sizes: [medium, wide]\n    fits: [grid]\n", 14,
             "fits \"grid\""),
        ]
        for (name, from, to, line, message) in cases {
            let edited = cliInlineBoard.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(edited, cliInlineBoard, name)
            let found = problem(edited)
            XCTAssertEqual(found?.line, line, "\(name): \(String(describing: found))")
            XCTAssertTrue(found?.message.contains(message) ?? false, "\(name): \(String(describing: found))")
        }
    }

    func testAnInlineProviderNeedsNoApprovalAndIsRead() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: clock
                title: Clock
                source: {kind: provider, name: app/clock, every: 60s}
                view: {kind: app.clock}
                frame: {x: 24, y: 24, w: 320, h: 160}
            """)
        XCTAssertEqual(board.widgets.first?.inline?.source, .provider(ProviderSource(name: "app/clock", with: [:], every: "60s")))
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
