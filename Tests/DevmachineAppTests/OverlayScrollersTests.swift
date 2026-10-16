import AppKit
import XCTest
@testable import DevmachineApp

@MainActor
final class OverlayScrollersTests: XCTestCase {
    private func scrollView(holding probe: OverlayScrollerProbe) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
        document.addSubview(probe)
        scroll.documentView = document
        scroll.scrollerStyle = .legacy
        return scroll
    }

    func testAttachingSetsTheEnclosingScrollViewToOverlay() {
        let probe = OverlayScrollerProbe(center: NotificationCenter())
        let scroll = scrollView(holding: probe)
        probe.apply()
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
    }

    func testAPreferenceChangeIsUndoneOnTheNextTurn() async {
        let center = NotificationCenter()
        let probe = OverlayScrollerProbe(center: center)
        let scroll = scrollView(holding: probe)
        probe.apply()
        scroll.scrollerStyle = .legacy
        center.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        await Task.yield()
        let applied = expectation(description: "applied")
        DispatchQueue.main.async { applied.fulfill() }
        await fulfillment(of: [applied], timeout: 1)
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
    }

    func testOtherNotificationsLeaveTheStyleAlone() async {
        let center = NotificationCenter()
        let probe = OverlayScrollerProbe(center: center)
        let scroll = scrollView(holding: probe)
        probe.apply()
        scroll.scrollerStyle = .legacy
        center.post(name: NSView.frameDidChangeNotification, object: nil)
        let drained = expectation(description: "drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 1)
        XCTAssertEqual(scroll.scrollerStyle, .legacy)
    }

    func testAProbeOutsideAScrollViewDoesNothing() {
        let probe = OverlayScrollerProbe(center: NotificationCenter())
        probe.apply()
        XCTAssertNil(probe.enclosingScrollView)
    }
}
