import XCTest
import AppKit
import SwiftTerm
@testable import DevmachineApp

/// The host copies through OSC 52: tmux writes the selection as an escape
/// sequence, and the terminal here is what has to put it on the Mac's
/// clipboard. Nothing else in the chain can be checked from a test, so this
/// covers the half that lives in this app.
@MainActor
final class ClipboardBridgeTests: XCTestCase {
    /// The copy crosses a hop to the main queue, so the test waits for it.
    private func waitForClipboard(_ expected: String) async throws -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if NSPasteboard.general.string(forType: .string) == expected { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    func testAnOSC52WriteReachesTheMacClipboard() async throws {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previous { pasteboard.setString(previous, forType: .string) }
        }

        let view = LegacyKeyboardTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let payload = Data("selected from the host".utf8).base64EncodedString()
        view.feed(text: "\u{1b}]52;c;\(payload)\u{7}")

        let arrived = try await waitForClipboard("selected from the host")
        XCTAssertTrue(arrived, "the host's copy never reached the Mac clipboard")
    }

    func testAQueryDoesNotWipeTheClipboard() async throws {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previous { pasteboard.setString(previous, forType: .string) }
        }
        pasteboard.clearContents()
        pasteboard.setString("kept", forType: .string)

        let view = LegacyKeyboardTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.feed(text: "\u{1b}]52;c;?\u{7}")
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(pasteboard.string(forType: .string), "kept")
    }
}
