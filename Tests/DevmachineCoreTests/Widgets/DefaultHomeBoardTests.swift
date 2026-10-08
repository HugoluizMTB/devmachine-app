import XCTest
@testable import DevmachineCore

final class DefaultHomeBoardTests: XCTestCase {
    private let widths = [1100, 1280, 1366, 1600, 2000, 2560]
    private let padding = 24
    private let gap = 16

    private func frame(_ layout: DefaultBoard.Layout, _ id: String) -> BoardFrame? { layout.spaced(id) }

    private func board(_ width: Int, harnesses: [String] = ["claude", "codex"], machines: Int = 3) -> DefaultBoard.Layout {
        DefaultBoard.layout(harnesses: harnesses, canvasWidth: width, machines: machines)
    }

    func testTheContractKeepsOnlyTheHarnessesItLists() {
        XCTAssertEqual(WidgetContract.current.allowed(["claude", "pi", "codex"], from: "harnesses"), ["claude", "codex"])
        XCTAssertEqual(WidgetContract.current.allowed(["main", "ghost"], from: "machines"), ["main", "ghost"])
    }

    func testOneHarnessIsWrittenAsTheCLIWritesIt() {
        XCTAssertEqual(BoardCodec.encode(DefaultBoard.make(harnesses: ["claude"])), """
            format: 1
            surface: home
            widgets:
              - id: machines
                type: devmachine-app/machines
                frame: {x: 24, y: 24, w: 576}
                size: auto
                minimized: false
                z: 1
              - id: clock
                type: devmachine-app/clock
                frame: {x: 840, y: 24, w: 416, h: 296}
                size: custom
                minimized: false
                z: 2
              - id: summary
                type: devmachine-app/summary
                frame: {x: 920, y: 336, w: 336}
                size: auto
                minimized: false
                z: 3
              - id: claude-usage
                type: devmachine-app/usage
                with: {harness: claude}
                frame: {x: 24, y: 176, w: 480}
                size: auto
                minimized: false
                z: 4

            """)
    }

    func testAnUnknownWidthLaysOutAt1280() {
        XCTAssertEqual(DefaultBoard.make(harnesses: ["claude", "codex"]), board(1280).board)
        XCTAssertEqual(DefaultBoard.make(harnesses: ["claude"], canvasWidth: 0), DefaultBoard.make(harnesses: ["claude"]))
    }

    func testAnUnknownMachineCountSizesTheRowForThree() {
        XCTAssertEqual(board(1600, machines: 0).board, board(1600, machines: 3).board)
    }

    func testTheFramesAt1280And1600And2000() {
        XCTAssertEqual(board(1280).board.widgets.map(\.frame), [
            BoardFrame(x: 24, y: 24, w: 576, h: 0),
            BoardFrame(x: 840, y: 24, w: 416, h: 296),
            BoardFrame(x: 920, y: 336, w: 336, h: 0),
            BoardFrame(x: 24, y: 176, w: 392, h: 0),
            BoardFrame(x: 432, y: 176, w: 392, h: 0),
        ])
        XCTAssertEqual(board(1600).board.widgets.map(\.frame), [
            BoardFrame(x: 24, y: 24, w: 576, h: 0),
            BoardFrame(x: 1160, y: 24, w: 416, h: 296),
            BoardFrame(x: 1240, y: 336, w: 336, h: 0),
            BoardFrame(x: 24, y: 176, w: 480, h: 0),
            BoardFrame(x: 520, y: 176, w: 480, h: 0),
        ])
        XCTAssertEqual(board(2000).board.widgets.map(\.frame), [
            BoardFrame(x: 24, y: 24, w: 576, h: 0),
            BoardFrame(x: 1560, y: 24, w: 416, h: 296),
            BoardFrame(x: 1640, y: 336, w: 336, h: 0),
            BoardFrame(x: 24, y: 176, w: 480, h: 0),
            BoardFrame(x: 520, y: 176, w: 480, h: 0),
        ])
    }

    func testTheMachinesTheSummaryAndTheUsageCardsFollowTheirContentAndTheClockIsFixed() {
        let widgets = board(1280).board.widgets
        for widget in widgets {
            XCTAssertEqual(widget.isAuto, widget.id != "clock", widget.id)
            XCTAssertEqual(widget.size, widget.id == "clock" ? "custom" : "auto", widget.id)
        }
    }

    func testNoTwoWidgetsOverlapAndAllFitTheWidthOnTheGrid() {
        for width in widths {
            for count in 0...4 {
                for machines in [1, 3, 6, 12] {
                    let label = "\(width) wide, \(count) harnesses, \(machines) machines"
                    let board = board(width, harnesses: Array(["claude", "codex", "kimi", "pi"].prefix(count)), machines: machines)
                    let spaced = board.board.widgets.compactMap { board.spaced($0.id) }
                    XCTAssertTrue(spaced.allSatisfy { $0.x % 8 == 0 && $0.y % 8 == 0 }, label)
                    XCTAssertTrue(spaced.allSatisfy { $0.w % 8 == 0 && $0.h % 8 == 0 }, label)
                    XCTAssertEqual(Set(board.board.widgets.map(\.z)).count, board.board.widgets.count, label)
                    let rects = spaced.map(\.rect)
                    for (i, a) in rects.enumerated() {
                        XCTAssertGreaterThanOrEqual(Int(a.minX), padding, label)
                        XCTAssertGreaterThanOrEqual(Int(a.minY), padding, label)
                        XCTAssertLessThanOrEqual(Int(a.maxX), width - padding, label)
                        for b in rects.dropFirst(i + 1) {
                            XCTAssertFalse(a.intersects(b), "\(label): \(a) and \(b)")
                        }
                    }
                }
            }
        }
    }

    func testTheMachinesRowShowsEveryMachineSideBySide() {
        let card = DefaultBoard.machineCard
        let spacing = DefaultBoard.machineCardSpacing
        for width in widths {
            for machines in 1...(width >= 1280 ? 4 : 3) {
                let row = try! XCTUnwrap(frame(board(width, machines: machines), "machines"))
                XCTAssertGreaterThanOrEqual(row.w, machines * card.w + (machines - 1) * spacing, "\(width) wide, \(machines)")
                XCTAssertGreaterThanOrEqual(row.h, card.h, "\(width) wide, \(machines)")
                XCTAssertLessThan(row.h, 2 * card.h + spacing, "\(width) wide, \(machines): one row")
            }
        }
    }

    func testMoreMachinesThanTheRowHoldsWrapToASecondRowAndStopThere() {
        let card = DefaultBoard.machineCard
        let row = try! XCTUnwrap(frame(board(1280, machines: 12), "machines"))
        XCTAssertGreaterThanOrEqual(row.h, 2 * card.h + DefaultBoard.machineCardSpacing)
        XCTAssertLessThan(row.h, 3 * card.h)
        let clock = try! XCTUnwrap(frame(board(1280, machines: 12), "clock"))
        XCTAssertLessThan(row.x + row.w, clock.x)
    }

    func testTheClockAndThePillShareTheRightEdgeAndThePillSitsUnderTheClock() {
        for width in widths {
            let board = board(width)
            let clock = try! XCTUnwrap(frame(board, "clock"))
            let summary = try! XCTUnwrap(frame(board, "summary"))
            let edge = (width - padding) / 8 * 8
            XCTAssertEqual(clock.x + clock.w, edge, "\(width)")
            XCTAssertEqual(summary.x + summary.w, edge, "\(width)")
            XCTAssertEqual(clock.y, padding, "\(width)")
            XCTAssertEqual(summary.y, clock.y + clock.h + gap, "\(width)")
            XCTAssertGreaterThanOrEqual(summary.w, DefaultBoard.summaryPillWidth, "\(width)")
        }
    }

    func testTheClockIsLargeOnACommonWindow() {
        for width in widths where width >= 1280 {
            let clock = try! XCTUnwrap(frame(board(width), "clock"))
            XCTAssertGreaterThanOrEqual(clock.w, 400, "\(width)")
            XCTAssertGreaterThanOrEqual(clock.h, 288, "\(width)")
        }
    }

    func testUsageSitsUnderTheMachinesTwoAcrossAndTallEnoughForItsWholeCard() {
        for width in widths {
            let board = board(width)
            let machines = try! XCTUnwrap(frame(board, "machines"))
            let claude = try! XCTUnwrap(frame(board, "claude-usage"))
            let codex = try! XCTUnwrap(frame(board, "codex-usage"))
            XCTAssertEqual(claude.y, machines.y + machines.h + gap, "\(width)")
            XCTAssertEqual(codex.y, claude.y, "\(width)")
            XCTAssertEqual(codex.x, claude.x + claude.w + gap, "\(width)")
            XCTAssertGreaterThanOrEqual(claude.h, DefaultBoard.usageContentHeight, "\(width)")
            XCTAssertGreaterThanOrEqual(claude.w, DefaultBoard.usageMinWidth, "\(width)")
        }
    }

    func testMoreHarnessesThanTheRowHoldsWrapToANewRow() {
        let board = board(1280, harnesses: ["claude", "codex", "kimi"])
        let claude = try! XCTUnwrap(frame(board, "claude-usage"))
        let kimi = try! XCTUnwrap(frame(board, "kimi-usage"))
        XCTAssertEqual(kimi.x, claude.x)
        XCTAssertEqual(kimi.y, claude.y + claude.h + gap)
        let wide = self.board(2000, harnesses: ["claude", "codex", "kimi"])
        XCTAssertEqual(frame(wide, "kimi-usage")?.y, frame(wide, "claude-usage")?.y)
    }

    func testEveryUsageWidgetShowsTheFullCardAndNamesItsHarness() {
        let layout = board(1280)
        let usage = layout.board.widgets.filter { $0.type == "devmachine-app/usage" }
        XCTAssertEqual(usage.map { $0.with["harness"] }, [.string("claude"), .string("codex")])
        XCTAssertTrue(usage.allSatisfy { (layout.spaced($0.id)?.h ?? 0) >= 240 })
    }

    func testNoHarnessKeepsMachinesClockAndPill() {
        let board = board(1280, harnesses: [])
        XCTAssertEqual(board.board.widgets.map(\.id), ["machines", "clock", "summary"])
        XCTAssertEqual(frame(board, "clock"), BoardFrame(x: 840, y: 24, w: 416, h: 296))
    }
}
