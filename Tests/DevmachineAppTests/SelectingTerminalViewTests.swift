import XCTest
import AppKit
import SwiftTerm
@testable import DevmachineApp

/// A pane whose program bytes are recorded instead of written to a process.
private final class RecordingTerminalView: SelectingTerminalView {
    var sent: [UInt8] = []
    var opened: [String] = []

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sent.append(contentsOf: data)
    }

    override func openRequestedLink(_ link: String, params: [String: String]) {
        opened.append(link)
    }
}

/// The pane owns selection in every session: a drag selects here even when
/// the program (tmux) asked for the mouse, and a plain click still reaches it.
@MainActor
final class SelectingTerminalViewTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var view: RecordingTerminalView!
    private var focused = true
    private var copyOnSelect = true

    private static let tmuxMouse = "\u{1b}[?1000h\u{1b}[?1002h\u{1b}[?1006h"

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("devmachine-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        view = RecordingTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.pasteboard = pasteboard
        view.paneIsFocused = { [unowned self] in focused }
        view.copiesOnSelect = { [unowned self] in copyOnSelect }
        view.feed(text: "alpha bravo charlie\r\ndelta echo\r\n")
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private var cell: CGSize {
        let size = view.terminalDimensions
        return CGSize(width: view.frame.width / CGFloat(size.cols), height: view.frame.height / CGFloat(size.rows))
    }

    private func point(col: Int, row: Int) -> NSPoint {
        NSPoint(x: (CGFloat(col) + 0.5) * cell.width, y: view.frame.height - (CGFloat(row) + 0.5) * cell.height)
    }

    private func mouse(_ type: NSEvent.EventType, _ at: NSPoint, clicks: Int = 1,
                       flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: at, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    private func drag(from: (Int, Int), to: (Int, Int)) {
        let start = point(col: from.0, row: from.1)
        let end = point(col: to.0, row: to.1)
        view.mouseDown(with: mouse(.leftMouseDown, start))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: (start.x + end.x) / 2, y: end.y)))
        view.mouseDragged(with: mouse(.leftMouseDragged, end))
        view.mouseUp(with: mouse(.leftMouseUp, end))
    }

    private func click(col: Int, row: Int, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) {
        let at = point(col: col, row: row)
        view.mouseDown(with: mouse(.leftMouseDown, at, clicks: clicks, flags: flags))
        view.mouseUp(with: mouse(.leftMouseUp, at, clicks: clicks, flags: flags))
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private var clipboard: String? { pasteboard.string(forType: .string) }

    func testADragSelectsFromWhereTheButtonWentDownAndCopies() async throws {
        drag(from: (6, 0), to: (11, 0))
        XCTAssertEqual(view.getSelection(), "bravo")
        XCTAssertEqual(clipboard, "bravo")
    }

    func testADragSelectsHereEvenWhenTmuxAskedForTheMouse() async throws {
        view.feed(text: Self.tmuxMouse)
        drag(from: (6, 0), to: (11, 0))
        try await settle()
        XCTAssertEqual(view.getSelection(), "bravo")
        XCTAssertEqual(clipboard, "bravo")
        XCTAssertEqual(view.sent, [], "tmux must not see the drag, or it starts its own selection")
    }

    func testAPlainClickStillReachesAProgramThatReadsTheMouse() async throws {
        view.feed(text: Self.tmuxMouse)
        click(col: 2, row: 1)
        try await settle()
        XCTAssertEqual(String(decoding: view.sent, as: UTF8.self), "\u{1b}[<0;3;2M\u{1b}[<0;3;2m")
    }

    func testAClickSendsNothingToAProgramThatDoesNotReadTheMouse() async throws {
        click(col: 2, row: 1)
        try await settle()
        XCTAssertEqual(view.sent, [])
    }

    func testAClickClearsASelectionEvenWhileTmuxHasTheMouse() async throws {
        drag(from: (0, 0), to: (4, 0))
        view.feed(text: Self.tmuxMouse)
        XCTAssertTrue(view.selectionActive)
        click(col: 2, row: 1)
        XCTAssertFalse(view.selectionActive)
    }

    func testAShakyClickIsStillAClick() async throws {
        pasteboard.setString("kept", forType: .string)
        let at = point(col: 2, row: 0)
        view.mouseDown(with: mouse(.leftMouseDown, at))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: at.x + 1, y: at.y)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: at.x + 1, y: at.y)))
        XCTAssertFalse(view.selectionActive)
        XCTAssertEqual(clipboard, "kept")
    }

    func testADoubleClickSelectsAWordAndATripleClickALine() async throws {
        view.feed(text: Self.tmuxMouse)
        click(col: 13, row: 0, clicks: 2)
        XCTAssertEqual(view.getSelection(), "charlie")
        XCTAssertEqual(clipboard, "charlie")
        click(col: 13, row: 0, clicks: 3)
        XCTAssertEqual(view.getSelection()?.trimmingCharacters(in: .whitespacesAndNewlines), "alpha bravo charlie")
    }

    /// A bare web address, which is all a program prints and all a multiplexer
    /// keeps after it repaints its screen.
    private func feedPlainLink() {
        view.feed(text: "see https://example.com/pr/42 now\r\n")
    }

    func testCommandAndAClickOpenABareWebAddress() async throws {
        feedPlainLink()
        click(col: 10, row: 2, flags: .command)
        XCTAssertEqual(view.opened, ["https://example.com/pr/42"])
    }

    func testOptionAndAClickOpenItToo() async throws {
        feedPlainLink()
        click(col: 10, row: 2, flags: .option)
        XCTAssertEqual(view.opened, ["https://example.com/pr/42"])
    }

    func testAPlainClickOnALinkOpensNothingAndStillReachesTheProgram() async throws {
        feedPlainLink()
        view.feed(text: Self.tmuxMouse)
        click(col: 10, row: 2)
        try await settle()
        XCTAssertEqual(view.opened, [])
        XCTAssertEqual(String(decoding: view.sent, as: UTF8.self), "\u{1b}[<0;11;3M\u{1b}[<0;11;3m")
    }

    func testTheModifiersOfAClickDoNotOutliveIt() async throws {
        feedPlainLink()
        click(col: 10, row: 2, flags: .command)
        XCTAssertEqual(view.opened.count, 1)
        view.requestOpenLink(source: view, link: "https://example.com/other", params: [:])
        XCTAssertEqual(view.opened, ["https://example.com/pr/42"])
    }

    func testCommandAndADragSelectsInsteadOfOpening() async throws {
        feedPlainLink()
        let start = point(col: 4, row: 2)
        let end = point(col: 29, row: 2)
        view.mouseDown(with: mouse(.leftMouseDown, start, flags: .command))
        view.mouseDragged(with: mouse(.leftMouseDragged, end, flags: .command))
        view.mouseUp(with: mouse(.leftMouseUp, end, flags: .command))
        XCTAssertEqual(view.opened, [])
        XCTAssertEqual(view.getSelection(), "https://example.com/pr/42")
    }

    func testCopyOnSelectOffLeavesTheClipboardAlone() async throws {
        copyOnSelect = false
        pasteboard.setString("kept", forType: .string)
        drag(from: (6, 0), to: (11, 0))
        XCTAssertEqual(view.getSelection(), "bravo")
        XCTAssertEqual(clipboard, "kept")
        view.copy(self)
        XCTAssertEqual(clipboard, "bravo")
    }

    func testCommandCWithNothingSelectedKeepsTheClipboard() {
        pasteboard.setString("kept", forType: .string)
        view.copy(self)
        XCTAssertEqual(clipboard, "kept")
    }

    func testTheSelectionHasTheColourTmuxIsGiven() {
        XCTAssertEqual(view.selectedTextBackgroundColor, SelectingTerminalView.selectionColor)
    }
}

/// A program copies through OSC 52 (tmux's copy mode, an editor's yank); the
/// pane puts it on the Mac's clipboard only while it has the keyboard.
@MainActor
final class TerminalClipboardGateTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var view: RecordingTerminalView!
    private var focused = true

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("devmachine-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        view = RecordingTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.pasteboard = pasteboard
        view.paneIsFocused = { [unowned self] in focused }
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private func write(_ text: String) {
        view.feed(text: "\u{1b}]52;c;\(Data(text.utf8).base64EncodedString())\u{7}")
    }

    private func waitForClipboard(_ expected: String) async throws -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if pasteboard.string(forType: .string) == expected { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    func testTheFocusedPanesWriteReachesTheClipboard() async throws {
        write("selected on the host")
        let arrived = try await waitForClipboard("selected on the host")
        XCTAssertTrue(arrived)
    }

    func testAPaneInTheBackgroundCannotWrite() async throws {
        focused = false
        pasteboard.setString("kept", forType: .string)
        write("from the background")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(pasteboard.string(forType: .string), "kept")
    }

    func testAQueryIsNotAnswered() async throws {
        pasteboard.setString("private", forType: .string)
        view.feed(text: "\u{1b}]52;c;?\u{7}")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(view.sent, [], "the host must not read the Mac's clipboard")
        XCTAssertEqual(pasteboard.string(forType: .string), "private")
    }

    func testThePaneStillTalksToItsProgram() async throws {
        view.feed(text: "\u{1b}[c")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(view.sent.isEmpty, "the device attributes reply must still reach the program")
    }
}
