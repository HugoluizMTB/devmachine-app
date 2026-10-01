import XCTest
import DevmachineCore
@testable import DevmachineApp

final class UpdateDialogContentTests: XCTestCase {
    private let release = GitHubRelease(
        tagName: "v0.1.3", body: "Faster start.\n\nsha256: \(String(repeating: "a", count: 64))")
    private let sessionsLine = "Your sessions keep running. Updating only restarts this app — every terminal and "
        + "agent, on this Mac or on your machines, carries on and is right where you left it when Devmachine reopens."

    func testADiskImageInstallSaysSessionsKeepRunning() {
        let content = UpdateDialogContent(release: release, current: SemanticVersion("0.1.2"), method: .manual)
        XCTAssertEqual(content.title, "Update Devmachine to 0.1.3")
        XCTAssertEqual(content.subtitle, "You have 0.1.2.")
        XCTAssertEqual(content.notes, "Faster start.")
        XCTAssertEqual(content.sessionsNote, sessionsLine)
        XCTAssertNil(content.homebrewCommand)
        XCTAssertEqual(content.primaryTitle, "Update and Relaunch")
    }

    func testAHomebrewInstallSaysTheSameAndShowsTheCommand() {
        let content = UpdateDialogContent(
            release: release, current: SemanticVersion("0.1.2"), method: .homebrew(brew: "/opt/homebrew/bin/brew"))
        XCTAssertEqual(content.sessionsNote, sessionsLine)
        XCTAssertEqual(content.homebrewCommand, "brew upgrade --cask devmachine-app")
        XCTAssertEqual(content.primaryTitle, "Update and Relaunch")
    }

    func testAnEmptyReleaseBodyHasNoNotes() {
        let content = UpdateDialogContent(
            release: GitHubRelease(tagName: "v0.1.3"), current: nil, method: .manual)
        XCTAssertEqual(content.notes, "")
        XCTAssertNil(content.subtitle)
    }


    func testAnUpdateThatCouldNotRelaunchSaysHowToFinish() {
        XCTAssertEqual(
            UpdateDialogContent.restartNeeded(version: "0.1.4"),
            "Updated to 0.1.4 — quit and reopen Devmachine to finish.")
    }

    func testTheCLIBlockSaysWhatTheButtonDoesAndWhatItLeavesAlone() {
        XCTAssertEqual(CLIUpdateContent.buttonTitle, "Update CLI")
        XCTAssertEqual(CLIUpdateContent.updated(SemanticVersion("0.8.0")!), "CLI updated to 0.8.0")
        XCTAssertTrue(CLIUpdateContent.scopeNote.contains("configuration, packages or machines"))
        XCTAssertEqual(CLIUpdateContent.terminalLead(manual: false), "Or run this in a terminal:")
        XCTAssertEqual(CLIUpdateContent.terminalLead(manual: true), "Run this once in a terminal:")
        XCTAssertTrue(CLIUpdateContent.needsManualUpdate(installed: SemanticVersion("0.7.22")!).contains("0.7.22"))
    }
}
