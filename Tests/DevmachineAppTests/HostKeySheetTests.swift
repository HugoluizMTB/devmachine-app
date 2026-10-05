import XCTest
import DevmachineCore
@testable import DevmachineApp

final class HostKeySheetTests: XCTestCase {
    @MainActor
    func testTheReviewOpensOverTheCurrentScreenAndClosesBackToIt() {
        let model = AppModel(store: SessionStore(runner: SilentRunner()))
        model.showPage(.setup)

        model.showHostKey("box")
        XCTAssertEqual(model.hostKeyMachine, "box")
        XCTAssertEqual(model.activePage, .setup)

        model.closeHostKey()
        XCTAssertNil(model.hostKeyMachine)
        XCTAssertEqual(model.activePage, .setup)
    }

    @MainActor
    func testTheReviewOpensOverATerminalWithoutLeavingIt() {
        let model = AppModel(store: SessionStore(runner: SilentRunner()))
        let ref = SessionRef(alias: "acme-devmachine", name: "dash")
        model.clickSession(ref)

        model.showHostKey("box")
        XCTAssertNil(model.activePage)
        XCTAssertEqual(model.selection, .session(alias: "acme-devmachine", name: "dash"))
    }

    func testTheWayOutSaysDoneOnlyOnceTheKeyIsTrusted() {
        XCTAssertEqual(HostKeyContent.closeTitle(phase: .trusted), "Done")
        XCTAssertEqual(HostKeyContent.closeTitle(phase: .matching), "Close")
        XCTAssertEqual(HostKeyContent.closeTitle(phase: .checking), "Close")
        XCTAssertEqual(HostKeyContent.closeTitle(phase: nil), "Close")
        XCTAssertEqual(HostKeyContent.closeTitle(phase: .needsNewerCLI), "Close")
    }

    func testTheSheetStaysOpenOnlyWhileTheKeyIsBeingWritten() throws {
        let report = try HostKeyReport.parse("""
        {"machine":"box","address":"203.0.113.7","status":"changed","key_type":"t",
         "current_fingerprint":"SHA256:old","presented_fingerprint":"SHA256:new","check":true,"changed":false}
        """)
        XCTAssertFalse(HostKeyContent.canClose(phase: .trusting(report)))
        XCTAssertTrue(HostKeyContent.canClose(phase: .review(report)))
        XCTAssertTrue(HostKeyContent.canClose(phase: .matching))
        XCTAssertTrue(HostKeyContent.canClose(phase: .failed(DMErrorState(title: "x", message: "y"))))
        XCTAssertTrue(HostKeyContent.canClose(phase: nil))
    }

    func testTheTitleNamesTheMachine() {
        XCTAssertEqual(HostKeyContent.sheetTitle(machine: "box"), "Host key · box")
    }
}

private struct SilentRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) { ("", "", 0) }
}
