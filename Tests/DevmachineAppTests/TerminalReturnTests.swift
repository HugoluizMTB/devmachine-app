import XCTest
import AppKit
@testable import DevmachineApp
import DevmachineCore

@MainActor
final class TerminalReturnTests: XCTestCase {
    private var sent: [(alias: String, command: String)] = []
    private var opened: [TerminalKind] = []
    private var windows: [NSWindow] = []
    private let checks = CheckLog()
    private var paused: Set<String> = []
    private var sweeping = false
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var reported: [String] = []

    override func setUp() {
        super.setUp()
        sent = []
        TerminalRegistry.shared.hostCommandRunner = { [weak self] alias, command in
            self?.sent.append((alias, command))
        }
        TerminalRegistry.shared.copyModeSchedule = CopyModeCheckSchedule()
        let checks = self.checks
        TerminalRegistry.shared.copyModeContext = TerminalRegistry.CopyModeContext(
            isPaused: { [unowned self] in paused.contains($0) },
            isSweeping: { [unowned self] in sweeping },
            machine: { ["acme-devmachine": "main", "beta-devmachine": "main"][$0] },
            now: { [unowned self] in now },
            report: { [unowned self] alias, failure in reported.append("\(alias) \(failure)") },
            run: { alias, command in checks.run(alias, command) })
    }

    override func tearDown() {
        for kind in opened { TerminalRegistry.shared.close(kind) }
        opened = []
        for window in windows { window.close() }
        windows = []
        TerminalRegistry.shared.hostCommandRunner = nil
        TerminalRegistry.shared.copyModeContext = nil
        TerminalRegistry.shared.copyModeSchedule = CopyModeCheckSchedule()
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

    func testComingBackToTheAppChecksEachAccountOnScreenOnceGroupedByMachine() async throws {
        open(.remote(alias: "acme-devmachine", session: "dash"), onScreen: true)
        open(.remote(alias: "acme-devmachine", session: "api"), onScreen: true)
        open(.remote(alias: "beta-devmachine", session: "main"), onScreen: true)

        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await waitFor { checks.calls.count == 2 }

        let byAlias = Dictionary(uniqueKeysWithValues: checks.calls.map { ($0.alias, $0.command) })
        XCTAssertEqual(
            byAlias["acme-devmachine"],
            RemoteCommands.leaveIdleCopyMode(session: "api") + "; "
                + RemoteCommands.leaveIdleCopyMode(session: "dash"))
        XCTAssertEqual(byAlias["beta-devmachine"], RemoteCommands.leaveIdleCopyMode(session: "main"))
    }

    func testASecondActivationSoonAfterLogsInNowhere() async throws {
        open(.remote(alias: "acme-devmachine", session: "dash"), onScreen: true)
        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await waitFor { checks.calls.count == 1 }
        try await settle()

        now = now.addingTimeInterval(60)
        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await settle()
        XCTAssertEqual(checks.calls.count, 1)

        now = now.addingTimeInterval(CopyModeCheckSchedule.defaultInterval)
        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await waitFor { checks.calls.count == 2 }
    }

    func testNothingLogsInWhileTheSweepRuns() async throws {
        open(.remote(alias: "acme-devmachine", session: "dash"), onScreen: true)

        sweeping = true
        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await settle()

        XCTAssertTrue(checks.calls.isEmpty)
    }

    func testAPausedWorkspaceIsNotCheckedAndTheOthersAre() async throws {
        open(.remote(alias: "acme-devmachine", session: "dash"), onScreen: true)
        open(.remote(alias: "beta-devmachine", session: "main"), onScreen: true)
        paused = ["acme-devmachine"]

        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await waitFor { checks.calls.count == 1 }
        try await settle()

        XCTAssertEqual(checks.calls.map(\.alias), ["beta-devmachine"])
    }

    func testARefusedLoginPausesThatWorkspaceAndTheRoundGoesOn() async throws {
        checks.failure = .authDenied
        open(.remote(alias: "acme-devmachine", session: "dash"), onScreen: true)
        open(.remote(alias: "gamma-devmachine", session: "web"), onScreen: true)

        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await waitFor { reported.count == 2 }
        try await settle()

        XCTAssertEqual(checks.calls.count, 2)
        XCTAssertEqual(Set(reported), ["acme-devmachine authDenied", "gamma-devmachine authDenied"])
    }

    func testAnUnreachableMachineEndsItsOwnChecksOnly() async throws {
        checks.failure = .unreachable
        open(.remote(alias: "acme-devmachine", session: "dash"), onScreen: true)
        open(.remote(alias: "beta-devmachine", session: "main"), onScreen: true)
        open(.remote(alias: "gamma-devmachine", session: "web"), onScreen: true)

        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()
        try await waitFor { reported.count == 2 }
        try await settle()

        XCTAssertEqual(Set(checks.calls.map(\.alias)), ["acme-devmachine", "gamma-devmachine"])
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testAPanePutAwayOrRunningOnThisMacIsNotChecked() {
        open(.remote(alias: "acme-devmachine", session: "hidden"), onScreen: false)
        open(.local(session: "here", path: NSTemporaryDirectory()), onScreen: true)

        TerminalRegistry.shared.leaveIdleCopyModeOnScreen()

        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(checks.calls.isEmpty)
    }
}

private final class CheckLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [(alias: String, command: String)] = []
    private var storedFailure: SSHFailure?
    var calls: [(alias: String, command: String)] { lock.withLock { stored } }
    var failure: SSHFailure? {
        get { lock.withLock { storedFailure } }
        set { lock.withLock { storedFailure = newValue } }
    }

    func run(_ alias: String, _ command: String) -> SSHFailure? {
        lock.withLock {
            stored.append((alias, command))
            return storedFailure
        }
    }
}
