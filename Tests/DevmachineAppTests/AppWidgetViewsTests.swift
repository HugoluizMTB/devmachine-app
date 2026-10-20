import XCTest
import SwiftUI
@testable import DevmachineApp
@testable import DevmachineCore

final class AppWidgetViewsTests: XCTestCase {
    func testTheClockFillsItsFrameWithoutPassingTheOldMaximum() {
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 320, height: 160), 80)
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 640, height: 320), 150)
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 160, height: 160), 57)
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 40, height: 40), 24)
    }

    func testUsageShowsOneLinePerWindowUntilTheWidgetIsFourRowsTall() {
        let heights = WidgetContract.presetOrder.map { (preset: $0, height: CGFloat(CanvasLayout.presetSize($0)!.h)) }
        let full = heights.filter { UsageWidgetLayout.showsFullCard(boardHeight: $0.height) }.map(\.preset)

        XCTAssertEqual(full, ["large", "tall"])
    }

    func testANarrowUsageWidgetDropsTheResetTime() {
        let widths = WidgetContract.presetOrder.map { (preset: $0, width: CGFloat(CanvasLayout.presetSize($0)!.w)) }
        let withoutReset = widths.filter { !UsageWidgetLayout.showsResetTime(boardWidth: $0.width) }.map(\.preset)

        XCTAssertEqual(withoutReset, ["small", "tall"])
    }

    func testAJobCarriesTheResolvedProviderCallAndInterval() {
        let job = AppWidgetJobs.job(
            for: instance(id: "usage"), resolved: resolved(provider: "app/harness-usage", every: 60, harness: "codex"),
            isOnScreen: true)

        XCTAssertEqual(job, WidgetJob(
            instanceID: "usage", key: WidgetRefreshKey(provider: "app/harness-usage", args: ["harness": "codex"]),
            every: 60, isActive: true))
    }

    func testAnAppProviderNeverRefreshesFasterThanFiveSeconds() {
        let job = AppWidgetJobs.job(
            for: instance(id: "usage"), resolved: resolved(provider: "app/harness-usage", every: 1, harness: "codex"),
            isOnScreen: true)

        XCTAssertEqual(job.every, 5)
    }

    func testAMinimizedWidgetAsksForNoRefresh() {
        let job = AppWidgetJobs.job(
            for: instance(id: "usage", minimized: true),
            resolved: resolved(provider: "app/harness-usage", every: 60, harness: "codex"), isOnScreen: true)

        XCTAssertFalse(job.isActive)
    }

    func testAWidgetOutOfSightAsksForNoRefresh() {
        let job = AppWidgetJobs.job(
            for: instance(id: "usage"), resolved: resolved(provider: "app/harness-usage", every: 60, harness: "codex"),
            isOnScreen: false)

        XCTAssertFalse(job.isActive)
    }

    private func instance(id: String, minimized: Bool = false) -> BoardWidget {
        BoardWidget(
            id: id, type: "codex/usage", frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium",
            minimized: minimized, z: 1)
    }

    private func resolved(provider: String, every: TimeInterval, harness: String) -> ResolvedWidget {
        let widget = CatalogWidget(
            name: "codex/usage", source: CatalogSource(name: provider, with: ["harness": harness], every: "60s"),
            viewKind: "app.harness-usage", sizes: ["medium"], defaultSize: "medium")
        return ResolvedWidget(
            widget: widget, provider: provider, viewKind: "app.harness-usage", arguments: ["harness": harness],
            every: every, minimum: CanvasSize(w: 160, h: 160))
    }

    func testTheHandleGripAndMenuCoverThePillAndAreAtLeast44PointsHigh() {
        for area in [WidgetChromeLayout.gripArea, WidgetChromeLayout.menuArea] {
            XCTAssertGreaterThanOrEqual(area.height, WidgetChromeLayout.pillHeight)
            XCTAssertGreaterThanOrEqual(area.height, 44)
        }
    }

    func testTheTopStripOfACardMovesIt() {
        let card = CGRect(x: 100, y: 200, width: 320, height: 160)
        let strip = WidgetChromeLayout.moveStrip
        XCTAssertGreaterThanOrEqual(strip, 44)
        XCTAssertTrue(WidgetChromeLayout.startsMove(at: CGPoint(x: 101, y: 201), in: card, strip: strip))
        XCTAssertTrue(WidgetChromeLayout.startsMove(at: CGPoint(x: 419, y: 200 + strip - 1), in: card, strip: strip))
        XCTAssertFalse(WidgetChromeLayout.startsMove(at: CGPoint(x: 200, y: 200 + strip + 1), in: card, strip: strip))
        XCTAssertFalse(WidgetChromeLayout.startsMove(at: CGPoint(x: 99, y: 210), in: card, strip: strip))
    }

    func testACardShorterThanTheStripMovesFromAnywhereOnIt() {
        let card = CGRect(x: 0, y: 0, width: 160, height: 30)
        XCTAssertTrue(WidgetChromeLayout.startsMove(at: CGPoint(x: 80, y: 29), in: card, strip: WidgetChromeLayout.moveStrip))
        XCTAssertFalse(WidgetChromeLayout.startsMove(at: CGPoint(x: 80, y: 31), in: card, strip: WidgetChromeLayout.moveStrip))
    }

    func testTheHandleGripAndMenuAreComfortableTargets() {
        XCTAssertGreaterThanOrEqual(WidgetChromeLayout.gripArea.width, DMHitSize.footer.width)
        XCTAssertGreaterThanOrEqual(WidgetChromeLayout.menuArea.width, DMHitSize.strip.width)
        XCTAssertGreaterThanOrEqual(WidgetChromeLayout.resizeCorner.width, DMHitSize.regular.width)
        XCTAssertGreaterThanOrEqual(WidgetChromeLayout.resizeCorner.height, DMHitSize.regular.height)
    }

    func testTheMoreChipNeverSitsUnderTheResizeCorner() {
        let corner = WidgetChromeLayout.resizeCorner
        let chip = CGSize(width: 96, height: DMControlHeight.small)
        for preset in WidgetContract.presetOrder {
            let size = CanvasLayout.presetSize(preset)!
            let card = CGSize(width: size.w, height: size.h)
            let cornerRect = WidgetOverlayPlacement.rect(of: corner, at: WidgetChromeLayout.resizeCornerAlignment, in: card)
            let chipRect = WidgetOverlayPlacement.rect(of: chip, at: MachinesWidgetView.moreChipAlignment, in: card)

            XCTAssertFalse(cornerRect.intersects(chipRect), preset)
        }
    }

    func testOverlayPlacementPutsAViewInTheCornerItIsAlignedTo() {
        let card = CGSize(width: 320, height: 160)
        let view = CGSize(width: 20, height: 10)

        XCTAssertEqual(WidgetOverlayPlacement.rect(of: view, at: .bottomTrailing, in: card), CGRect(x: 300, y: 150, width: 20, height: 10))
        XCTAssertEqual(WidgetOverlayPlacement.rect(of: view, at: .bottomLeading, in: card), CGRect(x: 0, y: 150, width: 20, height: 10))
        XCTAssertEqual(WidgetOverlayPlacement.rect(of: view, at: .top, in: card), CGRect(x: 150, y: 0, width: 20, height: 10))
    }
}
