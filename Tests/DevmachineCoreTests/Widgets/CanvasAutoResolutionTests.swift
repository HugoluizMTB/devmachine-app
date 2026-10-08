import XCTest
@testable import DevmachineCore

final class CanvasAutoResolutionTests: XCTestCase {
    private let catalog = CatalogFixtures.catalog([CatalogFixtures.clock, CatalogFixtures.summary, CatalogFixtures.machines])

    private func entry(_ type: String, size: String, h: Int = 0) -> BoardWidget {
        BoardWidget(id: "w", type: type, frame: BoardFrame(x: 0, y: 0, w: 320, h: h), size: size, z: 1)
    }

    func testAGrowingViewTakesAutoOnHome() {
        guard case let .ready(resolved) = WidgetResolution.resolve(entry("devmachine-app/summary", size: "auto"), in: catalog)
        else { return XCTFail("not ready") }
        XCTAssertTrue(resolved.grows)
        XCTAssertEqual(resolved.minimum, CanvasSize(w: 320, h: 40))
    }

    func testAViewThatDoesNotGrowKeepsTodaysMinimum() {
        guard case let .ready(resolved) = WidgetResolution.resolve(entry("devmachine-app/clock", size: "medium", h: 160), in: catalog)
        else { return XCTFail("not ready") }
        XCTAssertFalse(resolved.grows)
        XCTAssertEqual(resolved.minimum, CanvasSize(w: 160, h: 160))
    }

    func testAutoOnAViewThatDoesNotGrowIsRefusedWithTheStacksMessage() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/clock", size: "auto"), in: catalog),
            .refused(
                type: "devmachine-app/clock",
                reason: "w: size auto follows the content, and the app.clock view does not grow: use small, medium"))
    }

    func testAnInlineGrowingViewIsReadyWithAutoAndNoHeightFloor() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: disk
                title: Disk
                source: {kind: command, run: uptime, target: local, every: 60s}
                view: {kind: text}
                frame: {x: 24, y: 40, w: 336}
                size: auto
            """)
        guard case let .ready(resolved) = WidgetResolution.resolveInline(board.widgets[0]) else { return XCTFail("not ready") }
        XCTAssertTrue(resolved.grows)
        XCTAssertEqual(resolved.minimum.h, 40)
    }
}
