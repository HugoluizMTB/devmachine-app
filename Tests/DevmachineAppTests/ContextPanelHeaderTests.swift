import XCTest
@testable import DevmachineApp

final class ContextPanelHeaderTests: XCTestCase {
    func testTheHeaderReachesPastTheTitleBar() {
        XCTAssertEqual(ContextPanelHeader.height(titleLine: 22, titlebar: 52), 53)
        XCTAssertEqual(ContextPanelHeader.height(titleLine: 22, titlebar: 0), 44)
        XCTAssertEqual(ContextPanelHeader.height(titleLine: 30, titlebar: 52), 60)
    }
}
