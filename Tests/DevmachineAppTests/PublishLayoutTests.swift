import XCTest
import DevmachineCore
@testable import DevmachineApp

final class PublishLayoutTests: XCTestCase {
    func testStatusViewsWinOverTheChooserAndTheBar() {
        XCTAssertEqual(PublishLayout.pick(state: .noneInstalled, hasSites: false, showsStatus: true, wantsChooser: true), .status)
    }

    func testNoProviderAndNoSitesIsTheChooser() {
        XCTAssertEqual(PublishLayout.pick(state: .noneInstalled, hasSites: false, showsStatus: false, wantsChooser: false), .chooser)
        XCTAssertEqual(
            PublishLayout.pick(state: .notSynced(provider: "hostinger", problem: .noZones), hasSites: false, showsStatus: false, wantsChooser: false),
            .chooser)
    }

    func testSitesWithoutAProviderKeepTheTableUnderABar() {
        XCTAssertEqual(PublishLayout.pick(state: .noneInstalled, hasSites: true, showsStatus: false, wantsChooser: false), .barAndTable)
        XCTAssertEqual(PublishLayout.pick(state: .noneInstalled, hasSites: true, showsStatus: false, wantsChooser: true), .chooser)
    }

    func testReadyOrUnknownIsThePlainTable() {
        XCTAssertEqual(PublishLayout.pick(state: .ready, hasSites: false, showsStatus: false, wantsChooser: true), .table)
        XCTAssertEqual(PublishLayout.pick(state: .unknown, hasSites: false, showsStatus: false, wantsChooser: false), .table)
    }
}
