import XCTest
@testable import DevmachineCore

final class SessionNameTests: XCTestCase {
    func testAPlainNameIsValid() {
        XCTAssertTrue(SessionName.isValid("dash"))
        XCTAssertTrue(SessionName.isValid("dash-2_b"))
    }

    func testASpaceOrADotIsRejected() {
        XCTAssertFalse(SessionName.isValid("nova sessao"))
        XCTAssertFalse(SessionName.isValid("dash.2"))
        XCTAssertFalse(SessionName.isValid("sessão"))
        XCTAssertFalse(SessionName.isValid("   "))
    }

    func testTheHintOnlyShowsForSomethingTyped() {
        XCTAssertNil(SessionName.hint(for: ""))
        XCTAssertNil(SessionName.hint(for: "dash"))
        XCTAssertNotNil(SessionName.hint(for: "nova sessao"))
    }

    func testTheSuggestionIsUsable() {
        XCTAssertEqual(SessionName.suggestion(for: "nova sessao"), "nova-sessao")
        XCTAssertEqual(SessionName.suggestion(for: "dash.2"), "dash-2")
        XCTAssertEqual(SessionName.suggestion(for: " a  b "), "a-b")
        XCTAssertTrue(SessionName.isValid(SessionName.suggestion(for: "nova sessao")))
    }
}
