import XCTest
@testable import DevmachineCore

final class CardGridFitTests: XCTestCase {
    private let card = CGSize(width: 184, height: 132)
    private let spacing = 12.0

    private func fit(_ preset: String, scale: Double) -> CardGridFit {
        let size = CanvasLayout.presetSize(preset)!
        return CardGridFit.fit(
            in: CGSize(width: Double(size.w) * scale, height: Double(size.h) * scale),
            card: CGSize(width: card.width * scale, height: card.height * scale), spacing: spacing * scale)
    }

    func testEachPresetAtFullSize() {
        XCTAssertEqual(fit("small", scale: 1), CardGridFit(columns: 1, rows: 1, scale: 160.0 / 184))
        XCTAssertEqual(fit("medium", scale: 1), CardGridFit(columns: 1, rows: 1, scale: 1))
        XCTAssertEqual(fit("large", scale: 1), CardGridFit(columns: 1, rows: 2, scale: 1))
        XCTAssertEqual(fit("wide", scale: 1), CardGridFit(columns: 3, rows: 1, scale: 1))
        XCTAssertEqual(fit("tall", scale: 1).columns, 1)
        XCTAssertEqual(fit("tall", scale: 1).rows, 2)
        XCTAssertEqual(fit("tall", scale: 1).scale, 160.0 / 184, accuracy: 0.0001)
    }

    func testEachPresetAtALargerTextSizeFitsTheSameCards() {
        for preset in WidgetContract.presetOrder {
            let large = fit(preset, scale: 1.3), base = fit(preset, scale: 1)
            XCTAssertEqual(large.columns, base.columns, preset)
            XCTAssertEqual(large.rows, base.rows, preset)
            XCTAssertEqual(large.scale, base.scale, accuracy: 0.0001, preset)
        }
    }

    func testWhatIsLeftOverBecomesTheMoreCount() {
        let grid = fit("large", scale: 1.3)
        XCTAssertEqual(grid.shown(of: 5), 2)
        XCTAssertEqual(grid.hidden(of: 5), 3)
        XCTAssertEqual(grid.shown(of: 1), 1)
        XCTAssertEqual(grid.hidden(of: 1), 0)
    }

    func testNothingFitsWhenThereIsNoRoom() {
        XCTAssertEqual(CardGridFit.fit(in: .zero, card: card, spacing: spacing).capacity, 0)
    }
}
