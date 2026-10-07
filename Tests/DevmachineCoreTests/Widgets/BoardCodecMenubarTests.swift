import XCTest
@testable import DevmachineCore

final class BoardCodecMenubarTests: XCTestCase {
    private let defaultMenubar = """
        format: 1
        surface: menubar
        widgets:
          - id: brand
            type: devmachine-app/brand
          - id: open-pull-requests
            type: devmachine-app/open-pull-requests

        """

    private let defaultPanel = """
        format: 1
        surface: menubar-panel
        widgets:
          - id: pull-requests-panel
            type: devmachine-app/pull-requests-panel
          - id: usage-panel
            type: devmachine-app/usage-panel

        """

    private let inlineSlot = """
        format: 1
        surface: menubar
        widgets:
          - id: brand
            type: devmachine-app/brand
          - id: load
            title: Load
            source: {kind: command, run: uptime, every: 60s}
            view:
              kind: text
              wrap: false
            fits: [slot]

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

    private func slot(_ extra: String) -> String {
        "format: 1\nsurface: menubar\nwidgets:\n  - id: a\n    type: x/a\n\(extra)"
    }

    private func tab(_ extra: String) -> String {
        "format: 1\nsurface: menubar-panel\nwidgets:\n  - id: a\n    type: x/a\n\(extra)"
    }

    func testTheDefaultMenubarBoardsAreWrittenAsTheCLIWritesThem() throws {
        XCTAssertEqual(BoardCodec.encodeStack(DefaultStackBoard.make(surface: "menubar")), defaultMenubar)
        XCTAssertEqual(BoardCodec.encodeStack(DefaultStackBoard.make(surface: "menubar-panel")), defaultPanel)
        XCTAssertEqual(try BoardCodec.decodeStack(defaultMenubar), DefaultStackBoard.make(surface: "menubar"))
        XCTAssertEqual(try BoardCodec.decodeStack(defaultPanel), DefaultStackBoard.make(surface: "menubar-panel"))
    }

    func testTheDefaultSidebarsStillTakeSizeAuto() {
        for surface in DefaultStackBoard.surfaces {
            XCTAssertTrue(DefaultStackBoard.make(surface: surface).entries.allSatisfy { $0.size == .auto }, surface)
        }
        for surface in DefaultStackBoard.menubarSurfaces {
            XCTAssertTrue(DefaultStackBoard.make(surface: surface).entries.allSatisfy { $0.size == nil }, surface)
        }
    }

    func testAFourthMenubarWidgetIsRefusedAtItsLine() {
        let text = """
            format: 1
            surface: menubar
            widgets:
              - id: a
                type: acme/a
              - id: b
                type: acme/b
              - id: c
                type: acme/c
              - id: d
                type: acme/d

            """
        XCTAssertEqual(problem(text), BoardProblem(line: 10, message: "the menubar holds 3 widgets: take one off"))
        XCTAssertNil(problem(text.replacingOccurrences(of: "  - id: d\n    type: acme/d\n", with: "")))
    }

    func testTheCountIsReportedBeforeAnythingWrongWithTheFourthWidget() {
        let text = slot("  - id: b\n    type: x/b\n  - id: c\n    type: x/c\n  - id: d\n    type: x/d\n    z: 1\n")
        XCTAssertEqual(problem(text), BoardProblem(line: 10, message: "the menubar holds 3 widgets: take one off"))
    }

    func testMenubarEntriesRefuseEveryForbiddenKeyAtItsLine() {
        let cases = [
            ("    frame: {x: 0, y: 0, w: 1, h: 1}\n", "a: a widget in the menu bar has no frame; its place is its position in the list"),
            ("    z: 1\n", "a: a widget in the menu bar has no z; its place is its position in the list"),
            ("    size: small\n", "a: a widget in the menu bar has no size: it is one line of text"),
            ("    collapsed: false\n", "a: a widget in the menu bar does not fold: take it off with widgets remove"),
            ("    minimized: false\n", "a: a widget in the menu bar does not fold: take it off with widgets remove"),
        ]
        for (line, message) in cases {
            XCTAssertEqual(problem(slot(line)), BoardProblem(line: 6, message: message), line)
        }
    }

    func testTheFirstForbiddenKeyByLineIsReported() {
        XCTAssertEqual(problem(slot("    z: 1\n    size: small\n")), BoardProblem(
            line: 6, message: "a: a widget in the menu bar has no z; its place is its position in the list"))
    }

    func testATabRefusesFrameZMinimizedAndCollapsed() {
        let cases = [
            ("    frame: {x: 0, y: 0, w: 1, h: 1}\n", "a: a tab in the menu bar popover has no frame; its place is its position in the list"),
            ("    z: 1\n", "a: a tab in the menu bar popover has no z; its place is its position in the list"),
            ("    minimized: false\n", "a: a tab in the menu bar popover does not fold: take it off with widgets remove"),
            ("    collapsed: true\n", "a: a tab in the menu bar popover does not fold: take it off with widgets remove"),
        ]
        for (line, message) in cases {
            XCTAssertEqual(problem(tab(line)), BoardProblem(line: 6, message: message), line)
        }
    }

    func testATabKeepsItsSizeAndWritesItBack() throws {
        let text = tab("    size: medium\n")
        let board = try BoardCodec.decodeStack(text)
        XCTAssertEqual(board.entries[0].size, .preset("medium"))
        XCTAssertEqual(BoardCodec.encodeStack(board), text)
    }

    func testATabKeepsASizeThatIsNoPresetBecauseItNeverReadsIt() throws {
        for written in ["huge", "\"3\""] {
            let text = tab("    size: \(written)\n")
            XCTAssertEqual(BoardCodec.encodeStack(try BoardCodec.decodeStack(text)), text, written)
        }
        XCTAssertEqual(problem(tab("    size: [small]\n")), BoardProblem(line: 6, message: "a: size is one word, such as medium"))
    }

    func testAnInlineSlotWidgetMustUseASlotView() {
        let gauge = inlineSlot
            .replacingOccurrences(of: "every: 60s}", with: "every: 60s, parse: number}")
            .replacingOccurrences(of: "  kind: text\n      wrap: false", with: "  kind: gauge")
        XCTAssertEqual(problem(gauge), BoardProblem(line: 9, message: "load: the gauge view cannot be drawn in the menu bar"))
    }

    func testAnInlineWidgetMustFitTheBoardsLayout() {
        let stackOnly = inlineSlot.replacingOccurrences(of: "fits: [slot]", with: "fits: [stack]")
        XCTAssertEqual(problem(stackOnly), BoardProblem(
            line: 12, message: "load: fits stack, and this board's area is laid out as slot"))
    }

    func testAViewDrawnOnlyInTabsCannotBeDrawnInTheMenuBar() {
        let text = slot("").replacingOccurrences(
            of: "  - id: a\n    type: x/a\n",
            with: "  - id: a\n    title: A\n    source: {kind: provider, name: app/usage-panel, every: 60s}\n    view: {kind: app.usage-panel}\n")
        XCTAssertEqual(problem(text), BoardProblem(line: 7, message: "a: the app.usage-panel view cannot be drawn in the menu bar"))
    }

    func testAViewDrawnOnlyInTheMenuBarIsRefusedInATab() {
        let text = tab("").replacingOccurrences(
            of: "  - id: a\n    type: x/a\n",
            with: "  - id: a\n    title: A\n    source: {kind: provider, name: app/brand, every: 60s}\n    view: {kind: app.brand}\n")
        XCTAssertEqual(problem(text), BoardProblem(
            line: 7, message: "a: the app.brand view is drawn only in slot, and this board's area is laid out as tabs"))
    }

    func testAnInlineSlotEntrySurvivesARewriteByteForByte() throws {
        var board = try BoardCodec.decodeStack(inlineSlot)
        XCTAssertEqual(BoardCodec.encodeStack(board), inlineSlot)
        board.moveUp("load")
        XCTAssertEqual(try BoardCodec.decodeStack(BoardCodec.encodeStack(board)).entries.map(\.id), ["load", "brand"])
    }

    func testASidebarStillRefusesCollapsedThatIsNotABool() {
        XCTAssertNotNil(problem("format: 1\nsurface: sidebar\nwidgets:\n  - id: a\n    type: x/a\n    collapsed: maybe\n"))
    }
}
