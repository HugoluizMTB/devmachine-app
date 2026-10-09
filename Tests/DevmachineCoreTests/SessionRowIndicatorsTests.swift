import XCTest
@testable import DevmachineCore

final class SessionRowIndicatorsTests: XCTestCase {
    private func make(
        _ indicators: SessionIndicators?, busy: Bool = true, branch: Bool = true,
        age: Bool = true, attention: Bool = true
    ) -> SessionRowIndicators {
        var settings = AppSettings.empty
        settings.showsBusySpinner = busy
        settings.showsBranch = branch
        settings.showsSessionAge = age
        settings.showsAttention = attention
        return SessionRowIndicators(indicators, settings: settings)
    }

    func testNilIndicatorsShowNothing() {
        let row = make(nil)
        XCTAssertEqual(row.leading, .none)
        XCTAssertNil(row.subtitle)
        XCTAssertNil(row.age)
    }

    func testBusyShowsSpinner() {
        XCTAssertEqual(make(SessionIndicators(busy: true)).leading, .spinner)
    }

    func testAttentionWinsOverBusy() {
        XCTAssertEqual(make(SessionIndicators(busy: true, attention: true)).leading, .attention)
    }

    func testAttentionOffFallsBackToSpinner() {
        let row = make(SessionIndicators(busy: true, attention: true), attention: false)
        XCTAssertEqual(row.leading, .spinner)
    }

    func testSpinnerOffHidesOnlySpinner() {
        let indicators = SessionIndicators(path: "/Users/alice/acme", branch: "main", ageSeconds: 120, busy: true)
        let row = make(indicators, busy: false)
        XCTAssertEqual(row.leading, .none)
        XCTAssertEqual(row.subtitle, "main")
        XCTAssertEqual(row.age, "2m")
    }

    func testBranchOffHidesOnlySubtitle() {
        let indicators = SessionIndicators(path: "/Users/alice/acme", branch: "main", ageSeconds: 120, busy: true)
        let row = make(indicators, branch: false)
        XCTAssertEqual(row.leading, .spinner)
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.age, "2m")
    }

    func testAgeOffHidesOnlyAge() {
        let indicators = SessionIndicators(path: "/Users/alice/acme", branch: "main", ageSeconds: 120, busy: true)
        let row = make(indicators, age: false)
        XCTAssertEqual(row.leading, .spinner)
        XCTAssertEqual(row.subtitle, "main")
        XCTAssertNil(row.age)
    }

    func testSubtitleUsesBranchThenFolder() {
        XCTAssertEqual(make(SessionIndicators(path: "/Users/alice/acme", branch: "feat/x")).subtitle, "feat/x")
        XCTAssertEqual(make(SessionIndicators(path: "/Users/alice/acme", branch: "")).subtitle, "acme")
        XCTAssertEqual(make(SessionIndicators(path: "/Users/alice/acme")).subtitle, "acme")
    }

    func testSubtitleIsNilForEmptyBranchAndRootOrEmptyPath() {
        XCTAssertNil(make(SessionIndicators(path: "/", branch: "")).subtitle)
        XCTAssertNil(make(SessionIndicators(path: "", branch: "")).subtitle)
        XCTAssertNil(make(SessionIndicators(path: nil, branch: nil)).subtitle)
    }

    func testFormatAgeBoundaries() {
        XCTAssertEqual(SessionRowIndicators.formatAge(0), "<1m")
        XCTAssertEqual(SessionRowIndicators.formatAge(59), "<1m")
        XCTAssertEqual(SessionRowIndicators.formatAge(60), "1m")
        XCTAssertEqual(SessionRowIndicators.formatAge(3599), "59m")
        XCTAssertEqual(SessionRowIndicators.formatAge(3600), "1h")
        XCTAssertEqual(SessionRowIndicators.formatAge(86399), "23h")
        XCTAssertEqual(SessionRowIndicators.formatAge(86400), "1d")
    }

    func testNilAgeShowsNoAgeText() {
        XCTAssertNil(make(SessionIndicators(branch: "main", ageSeconds: nil)).age)
    }
}
