import XCTest
import AppKit
@testable import DevmachineApp

final class TerminalContainerViewTests: XCTestCase {
    /// `needsDisplay` only sticks on a view that lives in a window, so the
    /// container is hosted in one for the length of the test.
    private var window: NSWindow?

    private func container(width: CGFloat, height: CGFloat) -> (TerminalPaneView.TerminalContainerView, NSView) {
        let container = TerminalPaneView.TerminalContainerView(
            frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.contentInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let content = NSView(frame: .zero)
        container.addSubview(content)
        container.content = content
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        self.window = window
        return (container, content)
    }

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    func testLayoutInsetsTheContent() {
        let (container, content) = container(width: 400, height: 300)
        container.layout()
        XCTAssertEqual(content.frame, NSRect(x: 10, y: 8, width: 380, height: 284))
    }

    func testLayoutAsksForARepaintEvenWhenTheFrameIsUnchanged() {
        let (container, content) = container(width: 400, height: 300)
        container.layout()
        content.needsDisplay = false
        container.layout()
        XCTAssertEqual(content.frame, container.contentFrame)
        XCTAssertTrue(content.needsDisplay)
    }

    func testContentFrameNeverCollapses() {
        let (container, _) = container(width: 4, height: 4)
        XCTAssertEqual(container.contentFrame.width, 1)
        XCTAssertEqual(container.contentFrame.height, 1)
    }

    func testTheNudgeChangesTheHeightAndKeepsTheWidth() {
        let frame = NSRect(x: 10, y: 8, width: 380, height: 284)
        let nudged = TerminalPaneView.nudged(frame)

        XCTAssertEqual(nudged.width, frame.width)
        XCTAssertEqual(nudged.height, 264)
        XCTAssertNotEqual(nudged, frame)
    }

    func testTheNudgeNeverCollapsesATinyPane() {
        let nudged = TerminalPaneView.nudged(NSRect(x: 0, y: 0, width: 100, height: 4))
        XCTAssertEqual(nudged.height, 1)
    }
}
