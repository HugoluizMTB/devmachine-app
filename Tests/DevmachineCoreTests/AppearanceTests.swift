import XCTest
@testable import DevmachineCore

final class AppearanceTests: XCTestCase {
    func testAValueInsideTheRangeIsKept() {
        XCTAssertEqual(Appearance.clampTerminalOpacity(0.5), 0.5)
        XCTAssertEqual(Appearance.clampTerminalFontSize(15), 15)
        XCTAssertEqual(Appearance.clampUIFontScale(1.2), 1.2)
    }

    func testAValueOutsideTheRangeIsPulledToTheNearestEnd() {
        XCTAssertEqual(Appearance.clampTerminalOpacity(0), 0.2)
        XCTAssertEqual(Appearance.clampTerminalOpacity(9), 1.0)
        XCTAssertEqual(Appearance.clampTerminalFontSize(2), 9)
        XCTAssertEqual(Appearance.clampUIFontScale(4), 1.6)
    }

    func testSomethingThatIsNotANumberFallsBack() {
        XCTAssertEqual(Appearance.clampUIFontScale(.nan), Appearance.defaultUIFontScale)
        XCTAssertEqual(
            Appearance.clampTerminalOpacity(.infinity), Appearance.defaultTerminalOpacity)
    }

    func testSettingsWrittenBeforeTheseFieldsDecodeToTheDefaults() throws {
        let json = """
        {"opsRepoPath":"/Users/alice/dev/ops","hostAlias":"acme",
         "publicIP":"203.0.113.10","baseDomain":"example.com"}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.terminalOpacity, Appearance.defaultTerminalOpacity)
        XCTAssertEqual(settings.terminalFontSize, Appearance.defaultTerminalFontSize)
        XCTAssertEqual(settings.uiFontScale, Appearance.defaultUIFontScale)
    }

    func testAStoredValueOutOfRangeIsBroughtBackWhenRead() throws {
        let json = """
        {"opsRepoPath":"/x","hostAlias":"acme","publicIP":"203.0.113.10",
         "baseDomain":"example.com","uiFontScale":99}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.uiFontScale, 1.6)
    }
}
