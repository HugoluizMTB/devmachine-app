import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

final class DMMetricsTests: XCTestCase {
    private let scales: [Double] = [0.8, 1, 1.3, 1.6]

    override func tearDown() {
        DMFont.scale = 1
        super.tearDown()
    }

    func testOneRemIsTheBodyTextSizeAtTheCurrentScale() {
        XCTAssertEqual(DMMetrics.baseFontSize, 13)
        XCTAssertEqual(DMMetrics(scale: 1).rem(1), 13)
        XCTAssertEqual(DMMetrics(scale: 1.6).rem(1), 21)
        XCTAssertEqual(DMMetrics(scale: 1).rem(22.0 / 13), 22)
    }

    func testAPointValueGrowsWithTheScaleAndLandsOnHalfPoints() {
        XCTAssertEqual(DMMetrics(scale: 1).pt(7), 7)
        XCTAssertEqual(DMMetrics(scale: 1.3).pt(7), 9)
        XCTAssertEqual(DMMetrics(scale: 0.8).pt(22), 17.5)
        XCTAssertEqual(DMMetrics(scale: 1.6).pt(0), 0)
    }

    func testAtOneHundredPercentEveryTokenIsTodaysPointValue() {
        let m = DMMetrics(scale: 1)
        XCTAssertEqual([m.space.xxs, m.space.xs, m.space.sm, m.space.md, m.space.lg, m.space.xl, m.space.xxl],
                       [2, 4, 6, 8, 12, 16, 24])
        XCTAssertEqual([m.control.small, m.control.regular, m.control.large], [22, 28, 34])
        XCTAssertEqual(
            [m.radius.terminal, m.radius.keyCap, m.radius.row, m.radius.control, m.radius.tile,
             m.radius.pill, m.radius.toast, m.radius.panel, m.radius.card, m.radius.bubble],
            [4, 5, 6, 7, 8, 10, 12, 14, 16, 20])
        XCTAssertEqual([m.icon.dot, m.icon.xs, m.icon.sm, m.icon.md, m.icon.lg], [7, 9.5, 11, 12.5, 20])
        XCTAssertEqual(m.hit.compact, CGSize(width: 18, height: 18))
        XCTAssertEqual(m.hit.regular, CGSize(width: 20, height: 20))
        XCTAssertEqual(m.hit.header, CGSize(width: 20, height: 16))
        XCTAssertEqual(m.hit.strip, CGSize(width: 22, height: 22))
        XCTAssertEqual(m.hit.footer, CGSize(width: 24, height: 24))
        XCTAssertEqual([m.row.horizontal, m.row.vertical, m.row.outer], [10, 7, 6])
        XCTAssertEqual(m.section.panel, EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        XCTAssertEqual(m.section.sidebarGroup, EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
        XCTAssertEqual(m.section.sidebarFooter, EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        XCTAssertEqual(
            [m.card.toast, m.card.banner, m.card.sheetSmall, m.card.sheet, m.card.sheetLarge,
             m.card.sheetWide, m.card.palette, m.card.errorState],
            [220, 300, 360, 420, 460, 520, 600, 440])
        XCTAssertEqual(m.pane.sidebar, DMPaneWidth(min: 200, ideal: 260, max: 460))
        XCTAssertEqual(m.pane.context, DMPaneWidth(min: 240, ideal: 300, max: 520))
    }

    func testEveryTokenGrowsByTheSameScale() {
        let base = DMMetrics(scale: 1)
        for scale in scales {
            let m = DMMetrics(scale: scale)
            func expect(_ value: CGFloat, _ point: CGFloat, _ name: String) {
                XCTAssertEqual(value, ((point * CGFloat(scale)) * 2).rounded() / 2, "\(name) at \(scale)")
            }
            expect(m.space.md, base.space.md, "space.md")
            expect(m.space.xxl, base.space.xxl, "space.xxl")
            expect(m.control.small, base.control.small, "control.small")
            expect(m.control.large, base.control.large, "control.large")
            expect(m.radius.row, base.radius.row, "radius.row")
            expect(m.radius.bubble, base.radius.bubble, "radius.bubble")
            expect(m.icon.xs, base.icon.xs, "icon.xs")
            expect(m.hit.footer.width, base.hit.footer.width, "hit.footer")
            expect(m.row.vertical, base.row.vertical, "row.vertical")
            expect(m.section.panel.leading, base.section.panel.leading, "section.panel")
            expect(m.card.toast, base.card.toast, "card.toast")
            expect(m.card.banner, base.card.banner, "card.banner")
            expect(m.pane.sidebar.ideal, base.pane.sidebar.ideal, "pane.sidebar")
        }
    }

    func testControlsGrowWithTheirTextSoNothingSpillsOut() {
        for scale in scales {
            let m = DMMetrics(scale: scale)
            DMFont.scale = scale
            let ratio = m.control.small / DMFont.size(DMButtonSize.small.metrics.fontSize)
            XCTAssertEqual(ratio, 2, accuracy: 0.1, "small button at \(scale)")
        }
    }

    func testTheCurrentMetricsFollowTheTextSizeSetting() {
        DMFont.scale = 1.3
        XCTAssertEqual(DMMetrics.current, DMMetrics(scale: 1.3))
        XCTAssertEqual(EnvironmentValues().dmMetrics, DMMetrics(scale: 1.3))
        DMFont.scale = 1
        XCTAssertEqual(EnvironmentValues().dmMetrics, DMMetrics(scale: 1))
    }

    func testAButtonSizeKeepsTodaysPointsAtOneHundredPercent() {
        XCTAssertEqual(DMButtonSize.small.metrics.height, 22)
        XCTAssertEqual(DMButtonSize.regular.metrics.height, 28)
        XCTAssertEqual(DMButtonSize.large.metrics.height, 34)
        XCTAssertEqual(DMButtonSize.small.metrics(in: DMMetrics(scale: 1.6)).height, 35)
        XCTAssertEqual(DMButtonSize.regular.metrics(in: DMMetrics(scale: 1.6)).horizontalPadding, 19)
    }

    func testThePaneWidthsAreStoredAtOneHundredPercent() {
        let m = DMMetrics(scale: 1.6)
        XCTAssertEqual(m.pt(260), 416)
        XCTAssertEqual(m.base(416), 260)
        XCTAssertEqual(DMMetrics(scale: 1).base(260), 260)
    }
}
