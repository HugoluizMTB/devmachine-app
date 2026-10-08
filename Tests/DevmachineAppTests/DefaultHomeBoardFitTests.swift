import XCTest
import SwiftUI
import DevmachineCore
import HarnessUsageKit
@testable import DevmachineApp

/// Draws the real views at the frames the default Home board gives them, so
/// the board's numbers stay tied to what the cards need.
@MainActor
final class DefaultHomeBoardFitTests: XCTestCase {
    private let widths = [1100, 1280, 1600, 2000, 2560]

    private static let week = (1...7).map { DayTokens(date: "2026-09-2\($0)", tokens: Int64($0) * 100_000) }

    private static let claude = HarnessUsageState(harnessID: "claude", snapshot: HarnessUsageSnapshot(
        planName: "Max",
        blocks: [
            UsageBlock(kind: .session, label: "Session", percent: 62, resets: "in 2h 10m"),
            UsageBlock(kind: .weeklyAll, label: "Weekly (all models)", percent: 41, resets: "Mon"),
            UsageBlock(kind: .weeklyModel, label: "Weekly (Opus)", percent: 28, resets: "Mon"),
        ],
        stats: UsageStats(
            dailyTotals: week,
            modelTotals: [
                ModelTokens(model: "claude-sonnet", tokens: 3_420_000),
                ModelTokens(model: "claude-opus", tokens: 1_150_000),
                ModelTokens(model: "claude-haiku", tokens: 550_000),
            ],
            todayTokens: 640_000, mostUsedModel: "claude-sonnet")), refreshedAt: Date())

    private static let codex = HarnessUsageState(harnessID: "codex", snapshot: HarnessUsageSnapshot(
        planName: "Plus",
        blocks: [
            UsageBlock(kind: .session, label: "codex · 5h", percent: 35, resets: "2026-10-07T18:00:00Z"),
            UsageBlock(kind: .weeklyAll, label: "codex · 1w", percent: 52, resets: "2026-10-12T18:00:00Z"),
        ],
        stats: UsageStats(dailyTotals: week, modelTotals: [], todayTokens: 410_000, mostUsedModel: nil),
        summaryMetrics: [
            UsageSummaryMetric(id: "lifetimeTokens", label: "Lifetime tokens", value: "120M"),
            UsageSummaryMetric(id: "peakDailyTokens", label: "Peak daily tokens", value: "4.1M"),
            UsageSummaryMetric(id: "currentStreakDays", label: "Current streak", value: "12 days"),
            UsageSummaryMetric(id: "longestStreakDays", label: "Longest streak", value: "30 days"),
            UsageSummaryMetric(id: "longestRunningTurnSec", label: "Longest turn", value: "900 sec"),
        ]), refreshedAt: Date())

    private func usageHeight(_ state: HarnessUsageState, width: Int) -> CGFloat {
        DMFitCheck.render(width: CGFloat(width), scale: 1) {
            HarnessUsageCardContent(
                state: state, title: "Usage", systemImage: "gauge", accent: .orange, onRefresh: {}, scrollsContent: false)
        }.size.height
    }

    private var machineCardHeight: CGFloat {
        let snapshot = StatsSnapshot(
            collectedAt: "2026-09-29T16:23:11+00:00",
            memory: .init(totalBytes: 16_000, usedBytes: 9_600, availableBytes: 6_400),
            swap: .init(totalBytes: 0, usedBytes: 0),
            disk: .init(path: "/", usedBytes: 0, availableBytes: 116_000_000_000, usedPercent: 42),
            load: .init(load1: 1.234, load5: 0, load15: 0),
            docker: .init(available: true, containers: []),
            users: [], ports: [], errors: [])
        return DMFitCheck.render(scale: 1) {
            MachineStatsCard(
                machine: StatsMachine(name: "main", firstAddress: nil),
                state: MachineStatsState(snapshot: snapshot, refreshedAt: Date()),
                containerCount: { _ in 3 }, action: {})
        }.size.height
    }

    func testTheBoardKnowsTheMachineCardItLaysOut() {
        XCTAssertEqual(CGFloat(DefaultBoard.machineCard.w), MachineStatsCard.width)
        XCTAssertEqual(CGFloat(DefaultBoard.machineCard.h), MachinesWidgetView.nominalCardHeight)
        XCTAssertEqual(CGFloat(DefaultBoard.machineCardSpacing), MachinesWidgetView.cardSpacing)
    }

    func testEveryUsageCardShowsItsWholeContentWithoutScrolling() {
        for width in widths {
            let layout = DefaultBoard.layout(harnesses: ["claude", "codex"], canvasWidth: width, machines: 3)
            for entry in layout.board.widgets where entry.type == "devmachine-app/usage" {
                let reserved = try! XCTUnwrap(layout.spaced(entry.id)).h
                for state in [Self.claude, Self.codex] {
                    let needed = usageHeight(state, width: entry.frame.w)
                    XCTAssertGreaterThan(needed, 400, "\(state.harnessID) drew its full card")
                    XCTAssertGreaterThanOrEqual(
                        CGFloat(reserved), needed, "\(entry.id) at \(width) wide reserves too little for \(state.harnessID)")
                    XCTAssertGreaterThanOrEqual(CGFloat(DefaultBoard.usageContentHeight), needed.rounded(.up))
                }
                XCTAssertTrue(entry.isAuto)
            }
        }
    }

    func testTheMachinesWidgetShowsEveryMachineWithNoMoreChip() {
        let card = CGSize(width: MachineStatsCard.width, height: machineCardHeight)
        for width in widths {
            for machines in 1...3 {
                let layout = DefaultBoard.layout(harnesses: ["claude", "codex"], canvasWidth: width, machines: machines)
                let frame = try! XCTUnwrap(layout.spaced("machines"))
                let fit = CardGridFit.fit(
                    in: CGSize(width: frame.w, height: frame.h), card: card, spacing: MachinesWidgetView.cardSpacing)
                XCTAssertEqual(fit.scale, 1, "\(width) wide, \(machines) machines: cards drawn smaller")
                XCTAssertEqual(fit.hidden(of: machines), 0, "\(width) wide, \(machines) machines")
                XCTAssertGreaterThanOrEqual(fit.columns, machines, "\(width) wide, \(machines) machines: one row")
            }
        }
    }

    func testTheClockDrawsLargeAndTheSummaryPillFitsItsFrame() {
        for width in widths {
            let board = DefaultBoard.make(harnesses: ["claude", "codex"], canvasWidth: width, machines: 3)
            let clock = try! XCTUnwrap(board.widgets.first { $0.id == "clock" }?.frame)
            let font = ClockWidgetSizing.fontSize(width: CGFloat(clock.w), height: CGFloat(clock.h))
            XCTAssertGreaterThanOrEqual(font, width >= 1280 ? 140 : 110, "\(width)")
            let content = DMFitCheck.render(scale: 1) {
                VStack(spacing: DMSpace.sm) {
                    Text(verbatim: "23:58").font(.dm(font, weight: .thin, design: .rounded)).lineLimit(1)
                    Text(verbatim: "Wednesday, 30 September").font(.dm(13, weight: .medium))
                    Text(verbatim: "Alice's MacBook Pro").font(.dm(13, weight: .medium))
                }
            }.size
            XCTAssertLessThanOrEqual(content.width, CGFloat(clock.w), "\(width)")
            XCTAssertLessThanOrEqual(content.height, CGFloat(clock.h), "\(width)")

            let summary = try! XCTUnwrap(board.widgets.first { $0.id == "summary" }?.frame)
            let pill = DMFitCheck.render(scale: 1) {
                HStack(spacing: DMSpace.sm) {
                    Text(verbatim: "24 sessions")
                    Text(verbatim: "·")
                    Text(verbatim: "12 with coding harnesses")
                    Text(verbatim: "·")
                    Text(verbatim: "18 workspaces")
                }
                .font(.dm(11, weight: .medium))
                .lineLimit(1)
                .padding(.vertical, DMSpace.md)
                .padding(.horizontal, DMSpace.lg)
            }.size
            XCTAssertLessThanOrEqual(pill.width, CGFloat(summary.w), "\(width)")
            XCTAssertLessThan(CGFloat(DefaultBoard.summaryPillWidth) - pill.width, 8, "the pill fills its frame, so it ends at the right edge")
        }
    }
}
