import XCTest
import AppKit
@testable import DevmachineApp
import DevmachineCore

@MainActor
final class TerminalReturnTests: XCTestCase {
    private var sent: [(alias: String, command: String)] = []
    private var opened: [TerminalKind] = []
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        sent = []
        TerminalRegistry.shared.hostCommandRunner = { [weak self] alias, command in
            self?.sent.append((alias, command))
        }
    }

    override func tearDown() {
        for kind in opened { TerminalRegistry.shared.close(kind) }
        opened = []
        for window in windows { window.close() }
        windows = []
        TerminalRegistry.shared.hostCommandRunner = nil
        super.tearDown()
    }

    private func open(_ kind: TerminalKind, onScreen: Bool) {
        let view = TerminalRegistry.shared.terminal(for: kind)
        opened.append(kind)
        guard onScreen else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        windows.append(window)
    }

    func testComingBackToARemotePaneRepaintsItAndLeavesAnIdleCopyMode() {
        let kind = TerminalKind.remote(alias: "acme-devmachine", session: "dash")
        open(kind, onScreen: true)

        TerminalRegistry.shared.requestRepaint(kind)

        XCTAssertEqual(sent.map(\.alias), ["acme-devmachine"])
        XCTAssertEqual(sent.map(\.command), [RemoteCommands.returnToSession(session: "dash")])
    }

    func testComingBackToTheAppChecksEveryRemotePaneOnScreenInOneCallPerMachine() {
        open(.remote(alias: "acme-devmachine", session: "dash"), onScreen: true)
        open(.remote(alias: "acme-devmachine", session: "api"), onScreen: true)
        open(.remote(alias: "beta-devmachine", session: "main"), onScreen: true)

        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()

        let byAlias = Dictionary(uniqueKeysWithValues: sent.map { ($0.alias, $0.command) })
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(
            byAlias["acme-devmachine"],
            RemoteCommands.leaveIdleCopyMode(session: "api") + "; "
                + RemoteCommands.leaveIdleCopyMode(session: "dash"))
        XCTAssertEqual(byAlias["beta-devmachine"], RemoteCommands.leaveIdleCopyMode(session: "main"))
    }

    func testAPanePutAwayOrRunningOnThisMacIsNotChecked() {
        open(.remote(alias: "acme-devmachine", session: "hidden"), onScreen: false)
        open(.local(session: "here", path: NSTemporaryDirectory()), onScreen: true)

        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()

        XCTAssertTrue(sent.isEmpty)
    }
}
