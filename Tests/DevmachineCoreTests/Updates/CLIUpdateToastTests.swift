import XCTest
@testable import DevmachineCore

final class CLIUpdateToastTests: XCTestCase {
    private let latest = SemanticVersion("0.8.0")

    func testANewCLIShowsTheToast() {
        XCTAssertTrue(CLIUpdateToast.shows(stage: .idle, latest: latest, laterVersion: nil))
    }

    func testNoNewCLIShowsNothing() {
        XCTAssertFalse(CLIUpdateToast.shows(stage: .idle, latest: nil, laterVersion: nil))
    }

    func testLaterHidesThatVersion() {
        XCTAssertFalse(CLIUpdateToast.shows(stage: .idle, latest: latest, laterVersion: "0.8.0"))
    }

    func testANewerVersionThanTheLaterOneShowsAgain() {
        XCTAssertTrue(CLIUpdateToast.shows(stage: .idle, latest: SemanticVersion("0.8.1"), laterVersion: "0.8.0"))
    }

    func testAnOlderLatestThanTheLaterOneStaysHidden() {
        XCTAssertFalse(CLIUpdateToast.shows(stage: .idle, latest: SemanticVersion("0.7.30"), laterVersion: "0.8.0"))
    }

    func testAnUnreadableLaterVersionHidesNothing() {
        XCTAssertTrue(CLIUpdateToast.shows(stage: .idle, latest: latest, laterVersion: "soon"))
    }

    func testAFailureAndTheManualCommandFollowTheLaterRule() {
        for stage in [CLIUpdateToast.Stage.failed, .manual] {
            XCTAssertTrue(CLIUpdateToast.shows(stage: stage, latest: latest, laterVersion: nil), "\(stage)")
            XCTAssertFalse(CLIUpdateToast.shows(stage: stage, latest: latest, laterVersion: "0.8.0"), "\(stage)")
        }
    }

    func testARunningUpdateAlwaysShows() {
        XCTAssertTrue(CLIUpdateToast.shows(stage: .running, latest: latest, laterVersion: "0.8.0"))
        XCTAssertTrue(CLIUpdateToast.shows(stage: .running, latest: nil, laterVersion: nil))
    }

    func testAFinishedUpdateShowsUntilClosed() {
        XCTAssertTrue(CLIUpdateToast.shows(stage: .updated(closed: false), latest: nil, laterVersion: nil))
        XCTAssertFalse(CLIUpdateToast.shows(stage: .updated(closed: true), latest: nil, laterVersion: nil))
    }
}
