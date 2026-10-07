import XCTest
@testable import DevmachineApp

final class FlowLayoutTests: XCTestCase {
    func testTwoMachineCardsShareARowInTheWidthHomeGivesThemAtALargerTextSize() {
        let m = DMMetrics(scale: 1.1)
        let card = CGSize(width: m.pt(MachineStatsCard.width), height: 100)

        let result = FlowLayout(spacing: MachinesWidgetView.cardSpacing, rowSpacing: MachinesWidgetView.cardSpacing)
            .arrange([card, card], in: m.pt(MachineStatsCard.width) * 2 + m.pt(MachinesWidgetView.cardSpacing), metrics: m)

        XCTAssertEqual(result.origins.map(\.y), [0, 0])
    }

    func testGapsScaleWithTheTextSizeOnce() {
        let m = DMMetrics(scale: 2)
        let item = CGSize(width: 10, height: 10)

        let result = FlowLayout(spacing: 6, rowSpacing: 4).arrange([item, item, item], in: 40, metrics: m)

        XCTAssertEqual(result.origins, [CGPoint(x: 0, y: 0), CGPoint(x: 22, y: 0), CGPoint(x: 0, y: 18)])
    }
}
