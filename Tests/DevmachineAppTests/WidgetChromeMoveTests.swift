import AppKit
import SwiftUI
import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class WidgetChromeMoveTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.close()
        window = nil
        super.tearDown()
    }

    private final class Moves {
        var translations: [CGSize] = []
        var ended = 0
    }

    private func host(resolution: WidgetResolution, moves: Moves) -> NSWindow {
        let widget = BoardWidget(
            id: "broken", type: "acme/missing", frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium", z: 1)
        let chrome = WidgetChromeView(
            widget: widget, resolution: resolution, release: "", title: "Broken", size: CGSize(width: 320, height: 160),
            editable: true,
            onMoveChanged: { moves.translations.append($0) }, onMoveEnded: { moves.ended += 1 },
            onResizeChanged: { _ in }, onResizeEnded: {}, onFront: {}, onPreset: { _ in },
            onMinimize: { _ in }, onRefresh: {}, onRemove: {})
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: chrome.frame(width: 400, height: 240))
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        self.window = window
        return window
    }

    private func send(_ type: NSEvent.EventType, _ point: NSPoint, to window: NSWindow) {
        let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        window.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    private func drag(in window: NSWindow, fromTop offset: CGFloat) {
        let card = CGRect(x: 40, y: 40, width: 320, height: 160)
        let start = NSPoint(x: card.midX, y: window.frame.height - card.minY - offset)
        send(.leftMouseDown, start, to: window)
        for step in 1...5 { send(.leftMouseDragged, NSPoint(x: start.x + CGFloat(step * 6), y: start.y - CGFloat(step * 4)), to: window) }
        send(.leftMouseUp, NSPoint(x: start.x + 30, y: start.y - 20), to: window)
    }

    func testTheTopStripOfAPlaceholderCardMovesIt() {
        let moves = Moves()
        let window = host(resolution: .notFound(type: "acme/missing"), moves: moves)
        drag(in: window, fromTop: 20)
        XCTAssertFalse(moves.translations.isEmpty)
        XCTAssertEqual(moves.translations.last?.width ?? 0, 30, accuracy: 1)
    }

    func testADragBelowTheStripDoesNotMoveTheCard() {
        let moves = Moves()
        let window = host(resolution: .notFound(type: "acme/missing"), moves: moves)
        drag(in: window, fromTop: 120)
        XCTAssertTrue(moves.translations.isEmpty)
    }
}
