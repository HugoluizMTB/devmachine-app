import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

/// Draws the growing views the way a Home widget on `auto` draws them, with
/// no height offered, and reads how tall they come out. `ImageRenderer` does
/// not lay out a `ScrollView`, which is why a view that hugs has none.
@MainActor
final class WidgetAutoHeightFitTests: XCTestCase {
    private let width: CGFloat = 320
    private let card = CGSize(width: 320, height: 0)

    private func height(width: CGFloat? = nil, _ view: () -> some View) -> CGFloat {
        DMFitCheck.render(width: width ?? self.width, scale: 1, view).size.height
    }

    private func source(_ view: WidgetView, parse: ParseMode = .text) -> ResolvedSource {
        let command = CommandSource(
            run: "df", script: nil, args: [], shell: false, target: .local, every: .interval(60), timeout: 30,
            mode: .poll, keep: 200, parse: parse)
        return ResolvedSource(
            source: .command(command), view: view, every: .interval(60), needsApproval: false, package: nil,
            packagePath: nil)
    }

    private func cardHeight(_ view: WidgetView, output: SourceOutput, parse: ParseMode = .text) -> CGFloat {
        var state = SourceWidgetState()
        state.output = output
        return height {
            SourceWidgetContent(
                title: "Disk", source: source(view, parse: parse), state: state, history: [], size: card, onRun: {}, hugs: true)
        }
    }

    func testTheSummaryIsAsTallAsItsPillNotItsOldBox() {
        let pill = height(width: 336) { SummaryPill(sessions: 13, harnessSessions: 12, workspaces: 6, hugs: true) }
        XCTAssertGreaterThan(pill, 20)
        XCTAssertLessThan(pill, 80, "the pill was in a 160 pt box")
    }

    private func machine(_ index: Int) -> StatsMachine { StatsMachine(name: "box-\(index)", firstAddress: nil) }

    private var snapshot: MachineStatsState {
        let snapshot = StatsSnapshot(
            collectedAt: "2026-09-29T16:23:11+00:00",
            memory: .init(totalBytes: 16_000, usedBytes: 9_600, availableBytes: 6_400),
            swap: .init(totalBytes: 0, usedBytes: 0),
            disk: .init(path: "/", usedBytes: 0, availableBytes: 116_000_000_000, usedPercent: 42),
            load: .init(load1: 1.234, load5: 0, load15: 0),
            docker: .init(available: true, containers: []),
            users: [], ports: [], errors: [])
        return MachineStatsState(snapshot: snapshot, refreshedAt: Date())
    }

    private func machinesHeight(_ count: Int, width: CGFloat = 600) -> CGFloat {
        let state = snapshot
        return height(width: width) {
            MachinesGridView(
                machines: (1...count).map(machine), size: CGSize(width: width, height: 0), hugs: true,
                state: { _ in state }, containerCount: { _ in 0 }, onOpen: { _ in }, onShowAll: {})
        }
    }

    func testMachinesGrowsWithTheCountAndNeverHidesOne() {
        let one = machinesHeight(1)
        XCTAssertEqual(machinesHeight(3), one, accuracy: 1, "three share a row at 600 wide")
        let rowStep = machinesHeight(4) - one
        XCTAssertGreaterThan(rowStep, 100, "a fourth machine opens a row")
        XCTAssertEqual(machinesHeight(7) - one, rowStep * 2, accuracy: 2, "each row costs the same")
        XCTAssertEqual(machinesHeight(13) - one, rowStep * 4, accuracy: 4, "no \"+N more\" past two rows")
    }

    func testMachinesInABoxStillStopAtItsHeight() {
        let state = snapshot
        let boxed = height(width: 600) {
            MachinesGridView(
                machines: (1...13).map(machine), size: CGSize(width: 600, height: 150), hugs: false,
                state: { _ in state }, containerCount: { _ in 0 }, onOpen: { _ in }, onShowAll: {})
        }
        XCTAssertEqual(boxed, 150, accuracy: 1)
        XCTAssertLessThan(boxed, machinesHeight(13))
    }

    func testANumberAndAStatusAreAsTallAsTheirText() {
        var number = WidgetView(kind: "number")
        number.value = "{{json.used}}"
        let numberHeight = cardHeight(number, output: .number(42), parse: .number)
        XCTAssertGreaterThan(numberHeight, 50)
        XCTAssertLessThan(numberHeight, 110, "a number was in a 160 pt box")
        let status = WidgetView(kind: "status")
        let statusHeight = cardHeight(status, output: .status(code: 200, latency: 0.1), parse: .text)
        XCTAssertLessThan(statusHeight, 110)
    }

    func testAListShowsEveryRow() {
        let list = WidgetView(kind: "list")
        let few = cardHeight(list, output: .lines((1...3).map { "item \($0)" }))
        let many = cardHeight(list, output: .lines((1...12).map { "item \($0)" }))
        XCTAssertEqual(many - few, 9 * ListWidgetView.rowHeight, accuracy: 1)
    }

    func testTextGrowsWithItsLinesAndWrapsToItsWidth() {
        let text = WidgetView(kind: "text")
        let short = cardHeight(text, output: .text("one line"))
        let long = cardHeight(text, output: .text((1...30).map { "line \($0)" }.joined(separator: "\n")))
        XCTAssertGreaterThan(long, short + 29 * 10)
        let wrapped = cardHeight(text, output: .text(String(repeating: "word ", count: 200)))
        XCTAssertGreaterThan(wrapped, short + 100, "a long line wraps instead of scrolling")
    }

    func testThePlainLinesViewHasNoScrollViewWhenItHugs() {
        let lines = (1...20).map { "row \($0)" }
        let hugging = height { TextLinesView(lines: lines, wrap: true, keepsColor: false, followsNewest: false, hugs: true) }
        XCTAssertGreaterThan(hugging, 20 * 10)
    }
}
