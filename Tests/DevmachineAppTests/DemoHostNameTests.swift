import XCTest
@testable import DevmachineApp

final class DemoHostNameTests: XCTestCase {
    func testDemoModeShowsAnInventedMacName() {
        XCTAssertEqual(HomeView.macName(demo: true), DemoData.macName)
        XCTAssertEqual(DemoData.macName, "acme-mbp")
    }

    func testANormalLaunchShowsThisMacsName() {
        XCTAssertEqual(
            HomeView.macName(demo: false),
            Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }
}
