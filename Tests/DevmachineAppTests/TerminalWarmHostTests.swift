import AppKit
import SwiftTerm
import XCTest
@testable import DevmachineApp

@MainActor
final class TerminalWarmHostTests: XCTestCase {
    func testTheOffScreenWindowNeverTakesFocusOrShows() {
        let window = TerminalRegistry.offScreenWindow()
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertTrue(window.collectionBehavior.contains(.transient))
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
    }

    func testAWarmTerminalHasARealGridBeforeAnyPaneShowsIt() throws {
        let window = TerminalRegistry.offScreenWindow()
        let content = try XCTUnwrap(window.contentView)
        let term = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        content.addSubview(term)
        term.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let size = TerminalRegistry.defaultPaneSize(of: term)
        term.frame = NSRect(origin: .zero, size: size)

        let grid = term.getWindowSize()
        XCTAssertEqual(Int(grid.ws_col), 120, accuracy: 2)
        XCTAssertEqual(Int(grid.ws_row), 36, accuracy: 1)
    }
}
