import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

final class AppWidgetViewsTests: XCTestCase {
    func testTheClockFillsItsFrameWithoutPassingTheOldMaximum() {
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 320, height: 160), 80)
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 640, height: 320), 150)
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 160, height: 160), 57)
        XCTAssertEqual(ClockWidgetSizing.fontSize(width: 40, height: 40), 24)
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
}
