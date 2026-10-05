import XCTest
@testable import DevmachineCore

final class CLIUpdateCommandTests: XCTestCase {
    func testACLIBeforeNoMachinesKeepsCLIOnly() {
        XCTAssertEqual(CLIUpdateCommand.forCLI(installed: SemanticVersion("0.7.23")!), .cliOnly)
        XCTAssertEqual(CLIUpdateCommand.forCLI(installed: SemanticVersion("0.7.30")!), .cliOnly)
    }

    func testACLIWithNoMachinesAlsoPinsPackagesAndUpdatesSkills() {
        XCTAssertEqual(CLIUpdateCommand.forCLI(installed: SemanticVersion("0.7.31")!), .noMachines)
        XCTAssertEqual(CLIUpdateCommand.forCLI(installed: SemanticVersion("0.8.0")!), .noMachines)
    }

    func testTheArgumentsNeverReachMachines() {
        XCTAssertEqual(CLIUpdateCommand.cliOnly.arguments, ["update", "--cli-only"])
        XCTAssertEqual(CLIUpdateCommand.noMachines.arguments, ["update", "--no-machines", "--format", "json"])
        XCTAssertEqual(
            CLIUpdateCommand.packagesOnly.arguments, ["update", "--no-machines", "--skip-cli", "--format", "json"])
        for command in [CLIUpdateCommand.cliOnly, .noMachines, .packagesOnly] {
            XCTAssertFalse(command.arguments.contains("--yes"))
            XCTAssertTrue(command.arguments.contains("--cli-only") || command.arguments.contains("--no-machines"))
        }
    }

    func testOnlyTheNoMachinesCommandsPrintJSON() {
        XCTAssertFalse(CLIUpdateCommand.cliOnly.printsJSON)
        XCTAssertTrue(CLIUpdateCommand.noMachines.printsJSON)
        XCTAssertTrue(CLIUpdateCommand.packagesOnly.printsJSON)
    }

    func testAnUnknownFlagIsTheCommandsOwn() {
        XCTAssertTrue(CLIUpdateCommand.noMachines.isUnknownFlag(["error: unknown flag: --no-machines"]))
        XCTAssertFalse(CLIUpdateCommand.noMachines.isUnknownFlag(["error: unknown flag: --cli-only"]))
        XCTAssertTrue(CLIUpdateCommand.cliOnly.isUnknownFlag(["error: unknown flag: --cli-only"]))
    }
}

final class CLIUpdateReportTests: XCTestCase {
    private let full = """
        {
          "cli": {"from": "0.7.31", "to": "0.8.0", "updated": true},
          "packages": {"from": "v32", "to": "v33", "pinned": true},
          "skills": {"updated": true}
        }
        """

    func testItReadsEveryStep() throws {
        let report = try XCTUnwrap(CLIUpdateReport.parse(Data(full.utf8)))
        XCTAssertEqual(report.cliFrom, "0.7.31")
        XCTAssertEqual(report.cliTo, "0.8.0")
        XCTAssertTrue(report.cliUpdated)
        XCTAssertEqual(report.packagesFrom, "v32")
        XCTAssertEqual(report.packagesTo, "v33")
        XCTAssertTrue(report.packagesPinned)
        XCTAssertTrue(report.skillsUpdated)
    }

    func testTheSummarySaysWhatChanged() throws {
        let report = try XCTUnwrap(CLIUpdateReport.parse(Data(full.utf8)))
        XCTAssertEqual(report.summary, "CLI updated to 0.8.0 · packages pinned v33 · skills updated")
        XCTAssertEqual(report.packagesAndSkills, ["packages pinned v33", "skills updated"])
    }

    func testASkippedCLIAndAnUnmovedPinReadPlainly() throws {
        let json = #"{"cli":{"from":"0.7.31","to":"0.7.31","updated":false},"packages":{"from":"v33","to":"v33","pinned":false},"skills":{"updated":false}}"#
        let report = try XCTUnwrap(CLIUpdateReport.parse(Data(json.utf8)))
        XCTAssertEqual(report.summary, "packages already on v33 · skills already current")
    }

    func testMissingStepsAndExtraFieldsAreTolerated() throws {
        let report = try XCTUnwrap(CLIUpdateReport.parse(Data(#"{"packages":{"to":"v33","pinned":true},"extra":1}"#.utf8)))
        XCTAssertFalse(report.cliUpdated)
        XCTAssertNil(report.cliTo)
        XCTAssertEqual(report.packagesTo, "v33")
        XCTAssertFalse(report.skillsUpdated)
        XCTAssertEqual(report.summary, "packages pinned v33 · skills already current")
    }

    func testTextAroundTheObjectIsIgnored() {
        let report = CLIUpdateReport.parse(Data("note: cached\n\(full)\n".utf8))
        XCTAssertEqual(report?.packagesTo, "v33")
    }

    func testNoJSONIsNoReport() {
        XCTAssertNil(CLIUpdateReport.parse(Data()))
        XCTAssertNil(CLIUpdateReport.parse(Data("==> CLI\n".utf8)))
        XCTAssertNil(CLIUpdateReport.parse(Data("[1, 2]".utf8)))
    }
}

final class PackagesOutdatedTests: XCTestCase {
    func testItReadsTheCLIsAnswer() throws {
        let json = #"{"pinned":"v32","latest":"v33","newer":true,"notes_url":"https://example.com/releases/v33"}"#
        let outdated = try PackagesOutdated.parse(Data(json.utf8))
        XCTAssertEqual(outdated, PackagesOutdated(
            pinned: "v32", latest: "v33", newer: true, notesURL: URL(string: "https://example.com/releases/v33")))
    }

    func testANotesURLIsOptional() throws {
        let outdated = try PackagesOutdated.parse(Data(#"{"pinned":"v33","latest":"v33","newer":false}"#.utf8))
        XCTAssertNil(outdated.notesURL)
        XCTAssertFalse(outdated.newer)
    }

    func testAnEmptyNotesURLIsNone() throws {
        let outdated = try PackagesOutdated.parse(
            Data(#"{"pinned":"v32","latest":"v33","newer":true,"notes_url":""}"#.utf8))
        XCTAssertNil(outdated.notesURL)
    }

    func testBrokenJSONThrows() {
        XCTAssertThrowsError(try PackagesOutdated.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try PackagesOutdated.parse(Data(#"{"pinned":"v32"}"#.utf8)))
    }
}

final class PackagesVersionTests: XCTestCase {
    func testTagsCompareByNumber() {
        XCTAssertLessThan(PackagesVersion("v9")!, PackagesVersion("v10")!)
        XCTAssertLessThan(PackagesVersion("v32")!, PackagesVersion("33")!)
        XCTAssertLessThan(PackagesVersion("v1.2")!, PackagesVersion("v1.10")!)
        XCTAssertEqual(PackagesVersion("v33")!, PackagesVersion("V33")!)
        XCTAssertEqual(PackagesVersion("v1")!, PackagesVersion("v1.0")!)
    }

    func testAnythingElseIsNotAVersion() {
        XCTAssertNil(PackagesVersion(""))
        XCTAssertNil(PackagesVersion("v"))
        XCTAssertNil(PackagesVersion("latest"))
        XCTAssertNil(PackagesVersion("v3x"))
    }
}

final class PackagesUpdateToastTests: XCTestCase {
    private let newer = PackagesOutdated(pinned: "v32", latest: "v33", newer: true, notesURL: nil)

    func testItAsksForTheCLIThatKnowsTheCommands() {
        XCTAssertFalse(PackagesUpdateToast.isSupported(installed: SemanticVersion("0.7.30")!))
        XCTAssertTrue(PackagesUpdateToast.isSupported(installed: SemanticVersion("0.7.31")!))
    }

    func testOnlyANewerReleaseIsOffered() {
        XCTAssertEqual(PackagesUpdateToast.offered(newer), newer)
        XCTAssertNil(PackagesUpdateToast.offered(PackagesOutdated(pinned: "v33", latest: "v33", newer: false, notesURL: nil)))
        XCTAssertNil(PackagesUpdateToast.offered(PackagesOutdated(pinned: "v32", latest: " ", newer: true, notesURL: nil)))
        XCTAssertNil(PackagesUpdateToast.offered(nil))
    }

    func testAnIdleToastShowsANewerReleaseNotPutOff() {
        XCTAssertTrue(PackagesUpdateToast.shows(stage: .idle, notice: newer, laterVersion: nil))
        XCTAssertFalse(PackagesUpdateToast.shows(stage: .idle, notice: nil, laterVersion: nil))
        XCTAssertFalse(PackagesUpdateToast.shows(stage: .idle, notice: newer, laterVersion: "v33"))
        XCTAssertTrue(PackagesUpdateToast.shows(stage: .failed, notice: newer, laterVersion: nil))
    }

    func testLaterHidesThatReleaseAndOlderOnesUntilANewerOne() {
        XCTAssertTrue(PackagesUpdateToast.isPutOff("v33", laterVersion: "v33"))
        XCTAssertTrue(PackagesUpdateToast.isPutOff("v9", laterVersion: "v10"))
        XCTAssertFalse(PackagesUpdateToast.isPutOff("v34", laterVersion: "v33"))
        XCTAssertFalse(PackagesUpdateToast.isPutOff("v33", laterVersion: nil))
        XCTAssertFalse(PackagesUpdateToast.isPutOff("v33", laterVersion: ""))
    }

    func testLaterWithTagsThatAreNotNumbersMatchesOnlyTheSameTag() {
        XCTAssertTrue(PackagesUpdateToast.isPutOff("edge", laterVersion: "edge"))
        XCTAssertFalse(PackagesUpdateToast.isPutOff("edge-2", laterVersion: "edge"))
    }

    func testARunningOrFinishedUpdateStaysWhateverLaterSaid() {
        XCTAssertTrue(PackagesUpdateToast.shows(stage: .running, notice: newer, laterVersion: "v33"))
        XCTAssertTrue(PackagesUpdateToast.shows(stage: .done(closed: false), notice: nil, laterVersion: "v33"))
        XCTAssertFalse(PackagesUpdateToast.shows(stage: .done(closed: true), notice: nil, laterVersion: nil))
    }

    func testAReportAtOrPastTheReleaseCoversIt() throws {
        let pinned = try XCTUnwrap(CLIUpdateReport.parse(Data(#"{"packages":{"to":"v33","pinned":true}}"#.utf8)))
        let behind = try XCTUnwrap(CLIUpdateReport.parse(Data(#"{"packages":{"to":"v32","pinned":false}}"#.utf8)))
        let none = try XCTUnwrap(CLIUpdateReport.parse(Data(#"{"skills":{"updated":true}}"#.utf8)))
        XCTAssertTrue(PackagesUpdateToast.isCovered(latest: "v33", by: pinned))
        XCTAssertFalse(PackagesUpdateToast.isCovered(latest: "v34", by: pinned))
        XCTAssertFalse(PackagesUpdateToast.isCovered(latest: "v33", by: behind))
        XCTAssertFalse(PackagesUpdateToast.isCovered(latest: "v33", by: none))
    }
}
