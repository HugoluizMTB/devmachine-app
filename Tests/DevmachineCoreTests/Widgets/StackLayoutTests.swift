import XCTest
@testable import DevmachineCore

final class StackLayoutTests: XCTestCase {
    private func resolved(_ name: String, view: String, sizes: [String], defaultSize: String = "") -> ResolvedWidget {
        let widget = CatalogWidget(
            name: name, source: CatalogSource(name: "app/clock", every: "60s"), viewKind: view, sizes: sizes,
            defaultSize: defaultSize)
        return ResolvedWidget(
            widget: widget, provider: "app/clock", viewKind: view, arguments: [:], every: 60,
            minimum: CanvasSize(w: 1, h: 1))
    }

    func testHeightsComeFromPresetRowsOrContent() {
        let clock = resolved("devmachine-app/clock", view: "app.clock", sizes: ["small", "medium", "large"], defaultSize: "medium")
        XCTAssertEqual(StackLayout.height(of: StackEntry(id: "c", type: "x/c", size: .preset("large")), resolved: clock), .points(160))
        XCTAssertEqual(StackLayout.height(of: StackEntry(id: "c", type: "x/c"), resolved: clock), .points(80))
        let links = resolved("devmachine-app/links", view: "app.links", sizes: [])
        XCTAssertEqual(StackLayout.height(of: StackEntry(id: "l", type: "x/l"), resolved: links), .auto)
        XCTAssertEqual(StackLayout.height(of: StackEntry(id: "l", type: "x/l", size: .auto), resolved: links), .auto)
        XCTAssertEqual(StackLayout.height(of: StackEntry(id: "l", type: "x/l", size: .preset("tall")), resolved: links), .points(160))
        let bare = resolved("acme/x", view: "text", sizes: [])
        XCTAssertEqual(StackLayout.height(of: StackEntry(id: "x", type: "acme/x"), resolved: bare), .points(80))
        XCTAssertEqual(StackLayout.placeholderHeight(), 80)
        XCTAssertEqual(StackLayout.approvalRows, 5)
    }

    func testTheEffectiveSizeIsTheEntrysThenAutoForAGrowingViewThenTheDefaultPreset() {
        let clock = resolved("x/c", view: "app.clock", sizes: ["small", "medium", "large"], defaultSize: "medium")
        XCTAssertEqual(StackLayout.effectiveSize(of: StackEntry(id: "c", type: "x/c"), resolved: clock), .preset("medium"))
        XCTAssertEqual(
            StackLayout.effectiveSize(of: StackEntry(id: "c", type: "x/c", size: .preset("large")), resolved: clock),
            .preset("large"))
        let firstSize = resolved("x/c", view: "app.clock", sizes: ["large", "small"])
        XCTAssertEqual(StackLayout.effectiveSize(of: StackEntry(id: "c", type: "x/c"), resolved: firstSize), .preset("large"))
        let bare = resolved("x/t", view: "text", sizes: [])
        XCTAssertEqual(StackLayout.effectiveSize(of: StackEntry(id: "t", type: "x/t"), resolved: bare), .preset("medium"))
        let links = resolved("x/l", view: "app.links", sizes: [])
        XCTAssertEqual(StackLayout.effectiveSize(of: StackEntry(id: "l", type: "x/l"), resolved: links), .auto)
    }

    func testSizeChoicesAreAutoForGrowingViewsThenAllowedPresets() {
        XCTAssertEqual(
            StackLayout.sizeChoices(for: resolved("x/l", view: "app.links", sizes: ["small", "large"])),
            [.auto, .preset("small"), .preset("large")])
        XCTAssertEqual(
            StackLayout.sizeChoices(for: resolved("x/c", view: "app.clock", sizes: ["medium", "small"])),
            [.preset("small"), .preset("medium")])
        XCTAssertEqual(StackLayout.sizeChoices(for: resolved("x/l", view: "app.links", sizes: [])), [.auto])
    }

    func testARowLandsPastANeighbourOnceItsMiddleIsCrossed() {
        let heights: [Double] = [40, 80, 40, 120]
        XCTAssertEqual(StackDragMath.targetIndex(from: 0, translation: 39, heights: heights), 0)
        XCTAssertEqual(StackDragMath.targetIndex(from: 0, translation: 41, heights: heights), 1)
        XCTAssertEqual(StackDragMath.targetIndex(from: 0, translation: 101, heights: heights), 2)
        XCTAssertEqual(StackDragMath.targetIndex(from: 0, translation: 10_000, heights: heights), 3)
        XCTAssertEqual(StackDragMath.targetIndex(from: 3, translation: -21, heights: heights), 2)
        XCTAssertEqual(StackDragMath.targetIndex(from: 3, translation: -10_000, heights: heights), 0)
        XCTAssertEqual(StackDragMath.targetIndex(from: 9, translation: 50, heights: heights), 9)
    }

    func testTheDropLineSitsInTheGap() {
        let heights: [Double] = [40, 80, 40]
        XCTAssertEqual(StackDragMath.indicatorY(from: 0, to: 1, heights: heights), 120)
        XCTAssertEqual(StackDragMath.indicatorY(from: 2, to: 0, heights: heights), 0)
        XCTAssertEqual(StackDragMath.indicatorY(from: 2, to: 1, heights: heights), 40)
    }
}
