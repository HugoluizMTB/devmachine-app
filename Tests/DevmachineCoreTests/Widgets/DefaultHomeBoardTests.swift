import XCTest
@testable import DevmachineCore

final class DefaultHomeBoardTests: XCTestCase {
    private func frame(_ board: Board, _ id: String) -> BoardFrame? { board.widgets.first { $0.id == id }?.frame }

    func testOneHarnessIsWrittenAsTheCLIWritesIt() {
        XCTAssertEqual(BoardCodec.encode(DefaultBoard.make(harnesses: ["claude"])), """
            format: 1
            surface: home
            widgets:
              - id: machines
                type: devmachine-app/machines
                frame: {x: 24, y: 24, w: 384, h: 320}
                size: custom
                minimized: false
                z: 1
              - id: clock
                type: devmachine-app/clock
                frame: {x: 680, y: 320, w: 320, h: 160}
                size: medium
                minimized: false
                z: 2
              - id: summary
                type: devmachine-app/summary
                frame: {x: 936, y: 616, w: 320, h: 160}
                size: medium
                minimized: false
                z: 3
              - id: claude-usage
                type: devmachine-app/usage
                with: {harness: claude}
                frame: {x: 24, y: 360, w: 384, h: 288}
                size: custom
                minimized: false
                z: 4

            """)
    }

    func testUsageIsTwoColumnsFromTwoHarnessesAndTheClockMovesOver() {
        let board = DefaultBoard.make(harnesses: ["claude", "codex", "kimi"])
        XCTAssertEqual(frame(board, "claude-usage"), BoardFrame(x: 24, y: 360, w: 384, h: 288))
        XCTAssertEqual(frame(board, "codex-usage"), BoardFrame(x: 424, y: 360, w: 384, h: 288))
        XCTAssertEqual(frame(board, "kimi-usage"), BoardFrame(x: 24, y: 664, w: 384, h: 288))
        XCTAssertEqual(frame(board, "clock"), BoardFrame(x: 880, y: 320, w: 320, h: 160))
    }

    func testNoTwoWidgetsOverlapAndAllFitTheWidth() {
        for count in 0...4 {
            let board = DefaultBoard.make(harnesses: Array(["claude", "codex", "kimi", "pi"].prefix(count)))
            let rects = board.widgets.map(\.frame.rect)
            XCTAssertTrue(board.widgets.allSatisfy { $0.frame.x % 8 == 0 && $0.frame.y % 8 == 0 }, "\(count) harnesses")
            XCTAssertEqual(Set(board.widgets.map(\.z)).count, board.widgets.count, "\(count) harnesses")
            for (i, a) in rects.enumerated() {
                XCTAssertLessThanOrEqual(a.maxX, 1256, "\(count) harnesses")
                for b in rects.dropFirst(i + 1) {
                    XCTAssertFalse(a.intersects(b), "\(count) harnesses: \(a) and \(b)")
                }
            }
        }
    }

    func testEveryUsageWidgetShowsTheFullCardAndNamesItsHarness() {
        let board = DefaultBoard.make(harnesses: ["claude", "codex"])
        let usage = board.widgets.filter { $0.type == "devmachine-app/usage" }
        XCTAssertEqual(usage.map { $0.with["harness"] }, [.string("claude"), .string("codex")])
        XCTAssertTrue(usage.allSatisfy { $0.frame.h >= 240 })
    }

    func testNoHarnessKeepsTheCardsColumnAndTheClockBesideIt() {
        let board = DefaultBoard.make(harnesses: [])
        XCTAssertEqual(board.widgets.map(\.id), ["machines", "clock", "summary"])
        XCTAssertEqual(frame(board, "clock"), BoardFrame(x: 680, y: 320, w: 320, h: 160))
    }
}
