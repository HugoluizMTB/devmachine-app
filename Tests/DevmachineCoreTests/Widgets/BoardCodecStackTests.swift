import XCTest
@testable import DevmachineCore

final class BoardCodecStackTests: XCTestCase {
    private let defaultContextText = """
        format: 1
        surface: context-sidebar
        widgets:
          - id: shortcuts
            type: devmachine-app/shortcuts
            size: auto
          - id: publish-port
            type: devmachine-app/publish-port
            size: auto
          - id: monitors
            type: devmachine-app/monitors
            size: auto
          - id: shells
            type: devmachine-app/shells
            size: auto
          - id: sub-agents
            type: devmachine-app/sub-agents
            size: auto
          - id: todo
            type: devmachine-app/todo
            size: auto
          - id: pull-requests
            type: devmachine-app/pull-requests
            size: auto
          - id: links
            type: devmachine-app/links
            size: auto

        """

    private let mixedText = """
        format: 1
        surface: context-sidebar
        widgets:
          - id: disk
            type: acme/disk
            with: {path: /}
            size: medium
            collapsed: true
          - id: here
            title: Where am I
            source: {kind: command, run: ls, args: ["{{context.path}}"], every: 30s}
            view:
              kind: text
              wrap: false
            sizes: [medium, large]
            size: large
          - id: links
            type: devmachine-app/links

        """

    private let inlineDisk = """
        format: 1
        surface: context-sidebar
        widgets:
          - id: disk
            title: Disk
            source: {kind: command, run: df, every: 60s}
            view: {kind: text}
            size: auto

        """

    private func problem(_ text: String) -> BoardProblem? {
        do {
            _ = try BoardCodec.decodeStack(text)
            return nil
        } catch let problem as BoardProblem {
            return problem
        } catch {
            XCTFail("unexpected \(error)")
            return nil
        }
    }

    private func typed(_ extra: String) -> String {
        "format: 1\nsurface: sidebar\nwidgets:\n  - id: a\n    type: x/a\n\(extra)"
    }

    func testTheDefaultContextSidebarIsWrittenAsTheCLIWritesIt() throws {
        XCTAssertEqual(BoardCodec.encodeStack(DefaultStackBoard.make(surface: "context-sidebar")), defaultContextText)
        XCTAssertEqual(try BoardCodec.decodeStack(defaultContextText), DefaultStackBoard.make(surface: "context-sidebar"))
    }

    func testAnEmptyStackIsAnEmptyList() throws {
        let empty = StackBoard(surface: "sidebar", entries: [])
        XCTAssertEqual(BoardCodec.encodeStack(empty), "format: 1\nsurface: sidebar\nwidgets: []\n")
        XCTAssertEqual(try BoardCodec.decodeStack("format: 1\nsurface: sidebar\nwidgets: []\n"), empty)
    }

    func testReadsTypedAndInlineEntriesInOrder() throws {
        let board = try BoardCodec.decodeStack(mixedText)
        XCTAssertEqual(board.entries.map(\.id), ["disk", "here", "links"])
        XCTAssertEqual(board.entries[0].with, ["path": .string("/")])
        XCTAssertEqual(board.entries[0].size, .preset("medium"))
        XCTAssertTrue(board.entries[0].collapsed)
        XCTAssertEqual(board.entries[1].inline?.title, "Where am I")
        XCTAssertEqual(board.entries[1].size, .preset("large"))
        XCTAssertNil(board.entries[2].size)
        XCTAssertFalse(board.entries[2].collapsed)
    }

    func testAnInlineStackEntrySurvivesARewriteByteForByte() throws {
        var board = try BoardCodec.decodeStack(mixedText)
        XCTAssertEqual(BoardCodec.encodeStack(board), mixedText)
        board.moveDown("disk")
        let moved = BoardCodec.encodeStack(board)
        XCTAssertTrue(moved.contains("""
              - id: here
                title: Where am I
                source: {kind: command, run: ls, args: ["{{context.path}}"], every: 30s}
                view:
                  kind: text
                  wrap: false
                sizes: [medium, large]
                size: large
            """))
        XCTAssertEqual(try BoardCodec.decodeStack(moved).entries.map(\.id), ["here", "disk", "links"])
    }

    func testCollapsedFalseIsLeftOutOnWrite() throws {
        let board = try BoardCodec.decodeStack(typed("    collapsed: false\n"))
        XCTAssertEqual(BoardCodec.encodeStack(board), typed(""))
    }

    func testAFrameZOrMinimizedIsRefusedWithItsLine() {
        XCTAssertEqual(problem(typed("    frame: {x: 0, y: 0, w: 1, h: 1}\n")), BoardProblem(
            line: 6, message: "a: a widget in a sidebar has no frame; its place is its position in the list"))
        XCTAssertEqual(problem(typed("    z: 3\n")), BoardProblem(
            line: 6, message: "a: a widget in a sidebar has no z; its place is its position in the list"))
        XCTAssertEqual(problem(typed("    minimized: false\n")), BoardProblem(
            line: 6, message: "a: a widget in a sidebar folds with collapsed: true, not minimized"))
    }

    func testSizeAndCollapsedMustBeWhatTheContractSays() {
        XCTAssertEqual(problem(typed("    size: huge\n")), BoardProblem(
            line: 6, message: "a: size \"huge\" in a sidebar is auto or one of small, medium, large, wide, tall"))
        XCTAssertEqual(problem(typed("    size: custom\n")), BoardProblem(
            line: 6, message: "a: size \"custom\" in a sidebar is auto or one of small, medium, large, wide, tall"))
        XCTAssertEqual(problem(typed("    collapsed: yes\n")), BoardProblem(
            line: 6, message: "collapsed of widget \"a\" must be true or false"))
    }

    func testATypedEntryLeavesCatalogRulesToResolution() throws {
        let board = try BoardCodec.decodeStack(typed("    size: auto\n  - id: b\n    type: x/a\n    size: tall\n"))
        XCTAssertEqual(board.entries.map(\.size), [.auto, .preset("tall")])
    }

    func testAnInlineWidgetMustFitAStackAndGrowForAuto() {
        XCTAssertEqual(problem(inlineDisk), BoardProblem(
            line: 8,
            message: "disk: size auto follows the content, and the text view does not grow: use small, medium, large, wide, tall"))
        let sized = inlineDisk.replacingOccurrences(of: "    size: auto", with: "    sizes: [small]\n    size: auto")
        XCTAssertEqual(problem(sized), BoardProblem(
            line: 9, message: "disk: size auto follows the content, and the text view does not grow: use small"))
        let outside = inlineDisk.replacingOccurrences(of: "    size: auto", with: "    sizes: [small]\n    size: large")
        XCTAssertEqual(problem(outside), BoardProblem(
            line: 9, message: "disk: size \"large\" in a sidebar is auto or one of small"))
        let canvasOnly = inlineDisk.replacingOccurrences(of: "    size: auto", with: "    fits: [canvas]")
        XCTAssertEqual(problem(canvasOnly), BoardProblem(
            line: 8, message: "disk: fits canvas, and this board's area is laid out as stack"))
    }

    private func contract(textLayouts: [String]) -> WidgetContract {
        let c = WidgetContract.current
        var views = c.views
        let text = views["text"]!
        views["text"] = WidgetContract.ViewSpec(accepts: text.accepts, fields: text.fields, layouts: textLayouts, grows: text.grows)
        return WidgetContract(
            engine: c.engine, layouts: c.layouts, unit: c.unit, snap: c.snap, presets: c.presets, stackRow: c.stackRow,
            stackEntry: c.stackEntry, slotMax: c.slotMax, slotEntry: c.slotEntry, tabsEntry: c.tabsEntry,
            surfaces: c.surfaces, contextTypes: c.contextTypes, providers: c.providers,
            packageProvider: c.packageProvider, views: views, sourceKinds: c.sourceKinds, sources: c.sources, formats: c.formats)
    }

    func testAnInlineViewDrawnOnlyOnACanvasIsRefused() throws {
        let fixed = inlineDisk.replacingOccurrences(of: "    size: auto\n", with: "")
        XCTAssertThrowsError(try BoardCodec.decodeStack(fixed, contract: contract(textLayouts: ["canvas"]))) { error in
            XCTAssertEqual(error as? BoardProblem, BoardProblem(
                line: 7, message: "disk: the text view is drawn only in canvas, and this board's area is laid out as stack"))
        }
        XCTAssertNoThrow(try BoardCodec.decodeStack(fixed, contract: contract(textLayouts: ["canvas", "stack"])))
    }

    func testAHandWrittenInlineEntryKeepsItsSourceAndViewAsWritten() throws {
        let handWritten = """
            format: 1
            surface: context-sidebar
            widgets:
              - id: probe
                title: "Probe #1"
                source:
                  every: 30s   # poll often
                  # the health page
                  url: "https://example.com/health?a=1"
                  kind: url
                  parse: json
                view:
                  item:
                    subtitle: 'state: {{item.state}}'
                    title: "{{item.name}}"
                    link: "{{item.url}}"
                  kind: list
                fits: [stack, canvas]
                size: large
                collapsed: true

            """
        let rewritten = """
            format: 1
            surface: context-sidebar
            widgets:
              - id: probe
                title: 'Probe #1'
                source:
                  every: 30s
                  url: "https://example.com/health?a=1"
                  kind: url
                  parse: json
                view:
                  item:
                    subtitle: 'state: {{item.state}}'
                    title: "{{item.name}}"
                    link: "{{item.url}}"
                  kind: list
                fits: [stack, canvas]
                size: large
                collapsed: true

            """
        let once = BoardCodec.encodeStack(try BoardCodec.decodeStack(handWritten))
        XCTAssertEqual(once, rewritten)
        XCTAssertEqual(BoardCodec.encodeStack(try BoardCodec.decodeStack(once)), once)
        let home = try BoardCodec.decode(
            handWritten.replacingOccurrences(of: "context-sidebar", with: "home")
                .replacingOccurrences(of: "    size: large\n    collapsed: true\n", with: "    frame: {x: 0, y: 0, w: 320, h: 320}\n"))
        let homeText = BoardCodec.encode(home)
        let body = { (text: String) in text.components(separatedBy: "\n").drop { !$0.contains("source:") }.prefix(10).joined(separator: "\n") }
        XCTAssertEqual(body(once), body(homeText))
    }

    func testAnUnknownSizeOrFitInAnInlineEntryNamesItsLine() {
        let sizes = inlineDisk.replacingOccurrences(of: "    size: auto", with: "    sizes: [small, huge]")
        XCTAssertEqual(problem(sizes), BoardProblem(
            line: 8, message: "size \"huge\" of widget \"disk\" is not one of small, medium, large, wide, tall"))
        let fits = inlineDisk.replacingOccurrences(of: "    size: auto", with: "    fits: [stack, shelf]")
        XCTAssertEqual(problem(fits), BoardProblem(
            line: 8, message: "fits \"shelf\" of widget \"disk\" is not one of canvas, stack, slot, tabs"))
    }

    func testAFrameIsReportedBeforeAnInlineProblem() {
        let both = inlineDisk.replacingOccurrences(of: "    title: Disk\n", with: "    frame: {x: 0, y: 0, w: 1, h: 1}\n")
        XCTAssertEqual(problem(both), BoardProblem(
            line: 5, message: "disk: a widget in a sidebar has no frame; its place is its position in the list"))
        let blockFrame = typed("    frame:\n      x: 0\n      y: 0\n      w: 1\n      h: 1\n")
        XCTAssertEqual(problem(blockFrame)?.line, 6)
    }

    func testInlineContextKeysAreTheArea() throws {
        let path = """
            format: 1
            surface: SURFACE
            widgets:
              - id: here
                title: Here
                source: {kind: command, run: ls, args: ["{{context.path}}"], every: 30s}
                view: {kind: text}

            """
        XCTAssertNoThrow(try BoardCodec.decodeStack(path.replacingOccurrences(of: "SURFACE", with: "context-sidebar")))
        let message = problem(path.replacingOccurrences(of: "SURFACE", with: "sidebar"))?.message ?? ""
        XCTAssertTrue(message.contains("needs context.path to be declared"), message)
    }

    func testAHomeFileIsNotAStack() {
        XCTAssertEqual(problem("format: 1\nsurface: home\nwidgets: []\n"), BoardProblem(
            line: 2, message: "surface home is a canvas; this file holds a stack of widgets"))
    }

    func testIDsAreUniqueAndCheckedLikeHome() {
        XCTAssertEqual(problem(typed("  - id: a\n    type: x/b\n")), BoardProblem(line: 6, message: "id \"a\" is used twice"))
    }

    func testAHomeWidgetRefusesCollapsedEvenWhenFalse() {
        let home = "format: 1\nsurface: home\nwidgets:\n  - id: a\n    type: x/a\n    frame: {x: 0, y: 0, w: 1, h: 1}\n    collapsed: false\n"
        XCTAssertThrowsError(try BoardCodec.decode(home)) { error in
            XCTAssertEqual(error as? BoardProblem, BoardProblem(
                line: 7, message: "a: a widget on a canvas folds with minimized: true, not collapsed"))
        }
    }
}
