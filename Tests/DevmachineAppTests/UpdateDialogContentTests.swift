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

    func testTheCLICardSaysItAlsoPinsPackagesFromNoMachinesOn() {
        XCTAssertEqual(CLIUpdateContent.toastNote(installed: SemanticVersion("0.7.30")!), CLIUpdateContent.toastNote)
        XCTAssertTrue(CLIUpdateContent.toastNote(installed: SemanticVersion("0.7.31")!).contains("only when you sync"))
        XCTAssertEqual(CLIUpdateContent.scopeNote(installed: SemanticVersion("0.7.23")!), CLIUpdateContent.scopeNote)
        XCTAssertTrue(CLIUpdateContent.scopeNote(installed: SemanticVersion("0.7.31")!).contains("packages release"))
    }

    func testTheCLIResultListsThePinAndSkills() {
        let report = CLIUpdateReport.parse(Data(
            #"{"cli":{"from":"0.7.31","to":"0.8.0","updated":true},"packages":{"from":"v32","to":"v33","pinned":true},"skills":{"updated":true}}"#.utf8))
        XCTAssertEqual(
            CLIUpdateContent.updated(SemanticVersion("0.8.0")!, report: report),
            "CLI updated to 0.8.0 · packages pinned v33 · skills updated")
        XCTAssertEqual(CLIUpdateContent.updated(SemanticVersion("0.8.0")!, report: nil), "CLI updated to 0.8.0")
        XCTAssertEqual(CLIUpdateContent.updatedNote(report: report), "Your machines change only when you sync.")
    }

    func testThePackagesCardWording() {
        XCTAssertEqual(PackagesUpdateContent.available("v33"), "Packages v33 is available")
        XCTAssertEqual(
            PackagesUpdateContent.note,
            "New packages and skills for your machines. Your machines change only when you sync.")
        XCTAssertEqual(PackagesUpdateContent.syncSuggestion, "Sync your machines from Settings → Machines")
        let report = CLIUpdateReport.parse(Data(#"{"packages":{"from":"v32","to":"v33","pinned":true},"skills":{"updated":true}}"#.utf8))
        XCTAssertEqual(PackagesUpdateContent.done(report), "Packages pinned v33 · skills updated")
        XCTAssertEqual(PackagesUpdateContent.done(nil), "Packages and skills updated")
    }

    func testTheAppCardNamesWhatItAlsoUpdates() {
        let cli = SemanticVersion("0.17.2")
        XCTAssertEqual(
            AppUpdateCardContent.title(version: "0.9.1", installed: false, cli: cli, packages: "v58"),
            "Devmachine 0.9.1 is available · also updates the CLI to 0.17.2 and packages to v58")
        XCTAssertEqual(
            AppUpdateCardContent.title(version: "0.9.1", installed: false, cli: cli, packages: nil),
            "Devmachine 0.9.1 is available · also updates the CLI to 0.17.2")
        XCTAssertEqual(
            AppUpdateCardContent.title(version: "0.9.1", installed: false, cli: nil, packages: "v58"),
            "Devmachine 0.9.1 is available · also updates packages to v58")
        XCTAssertEqual(
            AppUpdateCardContent.title(version: "0.9.1", installed: false, cli: nil, packages: nil),
            "Devmachine 0.9.1 is available")
        XCTAssertEqual(
            AppUpdateCardContent.title(version: "0.9.1", installed: true, cli: cli, packages: "v58"),
            "Devmachine 0.9.1 is installed")
    }

    func testTheDialogStepsWording() {
        let notice = CLIUpdateNotice(
            installed: SemanticVersion("0.7.31")!, latest: SemanticVersion("0.8.0")!,
            command: "brew upgrade devmachine", releaseURL: nil)
        let packages = PackagesOutdated(pinned: "v32", latest: "v33", newer: true, notesURL: nil)
        XCTAssertEqual(
            UnifiedUpdateContent.toolsDetail(cli: notice, packages: packages), "CLI 0.7.31 → 0.8.0 · packages v32 → v33")
        XCTAssertEqual(UnifiedUpdateContent.toolsDetail(cli: notice, packages: nil), "CLI 0.7.31 → 0.8.0")
        XCTAssertEqual(UnifiedUpdateContent.toolsDetail(cli: nil, packages: packages), "packages v32 → v33")
        XCTAssertEqual(UnifiedUpdateContent.toolsDetail(cli: nil, packages: nil), "Up to date")
        XCTAssertEqual(UnifiedUpdateContent.updateOnlyTheAppTitle, "Update only the app")
        XCTAssertEqual(UnifiedUpdateContent.status(.upToDate), "Up to date")
        XCTAssertEqual(UnifiedUpdateContent.status(.couldNotCheck), "Could not check")
        XCTAssertEqual(UnifiedUpdateContent.status(.skipped), "Skipped")
        XCTAssertEqual(UnifiedUpdateContent.status(.running), "Running")
        XCTAssertEqual(UnifiedUpdateContent.status(.done), "Done")
        XCTAssertEqual(UnifiedUpdateContent.status(.failed), "Failed")
        XCTAssertEqual(UnifiedUpdateContent.status(.waiting), "Waiting")
        XCTAssertEqual(UnifiedUpdateContent.status(.moveByHand), "Move it by hand")
    }

    func testTheStepsFollowTheToolsAndTheAppPhases() {
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .idle, toolsBehind: true, phase: .idle),
            UnifiedUpdateSteps(tools: .waiting, app: .waiting, relaunch: .waiting))
        XCTAssertEqual(UnifiedUpdateSteps(tools: .idle, toolsBehind: false, phase: .idle).tools, .upToDate)
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .idle, toolsBehind: false, toolsKnown: false, phase: .idle).tools, .couldNotCheck)
        XCTAssertEqual(UnifiedUpdateSteps(tools: .unknown, toolsBehind: false, phase: .idle).tools, .couldNotCheck)
        XCTAssertEqual(UnifiedUpdateSteps(tools: .running, toolsBehind: true, phase: .idle).tools, .running)
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .done, toolsBehind: false, phase: .downloading(0.4)),
            UnifiedUpdateSteps(tools: .done, app: .running, relaunch: .waiting))
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .upToDate, toolsBehind: false, phase: .upgradingWithHomebrew),
            UnifiedUpdateSteps(tools: .upToDate, app: .running, relaunch: .waiting))
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .done, toolsBehind: false, phase: .relaunching),
            UnifiedUpdateSteps(tools: .done, app: .done, relaunch: .running))
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .done, toolsBehind: false, phase: .restartNeeded("0.1.3")),
            UnifiedUpdateSteps(tools: .done, app: .done, relaunch: .waiting))
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .done, toolsBehind: false, phase: .failed(DMErrorState(title: "x", message: "y"))),
            UnifiedUpdateSteps(tools: .done, app: .failed, relaunch: .waiting))
        XCTAssertEqual(
            UnifiedUpdateSteps(tools: .needsManualUpdate("brew upgrade devmachine"), toolsBehind: true, phase: .idle).tools,
            .failed)
        XCTAssertEqual(UnifiedUpdateSteps(tools: .bypassed, toolsBehind: true, phase: .idle).tools, .skipped)
        XCTAssertEqual(
            UnifiedUpdateSteps(
                tools: .done, toolsBehind: false, phase: .manualMove(URL(fileURLWithPath: "/tmp/Devmachine.app"))),
            UnifiedUpdateSteps(tools: .done, app: .moveByHand, relaunch: .skipped))
    }
}
