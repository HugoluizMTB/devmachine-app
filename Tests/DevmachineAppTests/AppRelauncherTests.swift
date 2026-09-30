import AppKit
import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class AppRelauncherTests: XCTestCase {
    private struct SpawnFailed: Error {}

    func testStartsTheHelperThenClosesSheetsThenQuits() throws {
        var steps: [String] = []
        let relauncher = AppRelauncher(
            spawnHelper: { command in steps.append("spawn \(command.arguments[2]) \(command.arguments[3])") },
            closeSheets: { steps.append("close sheets") },
            terminate: { steps.append("terminate") },
            processID: 4242)

        try relauncher.relaunch(URL(fileURLWithPath: "/Applications/Devmachine.app"))

        XCTAssertEqual(steps, ["spawn /Applications/Devmachine.app 4242", "close sheets", "terminate"])
    }

    func testAHelperThatCannotStartLeavesTheAppRunning() {
        var steps: [String] = []
        let relauncher = AppRelauncher(
            spawnHelper: { _ in throw SpawnFailed() },
            closeSheets: { steps.append("close sheets") },
            terminate: { steps.append("terminate") },
            processID: 4242)

        XCTAssertThrowsError(try relauncher.relaunch(URL(fileURLWithPath: "/Applications/Devmachine.app")))
        XCTAssertEqual(steps, [])
    }

    func testEveryAttachedSheetIsEndedSoNothingBlocksQuitting() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered,
            defer: false)
        let inner = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.beginSheet(sheet)
        sheet.beginSheet(inner)
        XCTAssertNotNil(window.attachedSheet)
        XCTAssertNotNil(sheet.attachedSheet)

        SheetCloser.closeAll(in: [window])

        XCTAssertNil(window.attachedSheet)
        XCTAssertNil(sheet.attachedSheet)
    }
}
