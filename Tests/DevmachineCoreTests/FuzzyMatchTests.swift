import XCTest
@testable import DevmachineCore

final class FuzzyMatchTests: XCTestCase {
    private func score(_ query: String, _ text: String) -> Int? {
        FuzzyMatch.score(query, text)
    }

    func testAnEmptyQueryMatchesEverythingWithZero() {
        XCTAssertEqual(score("", "Stats"), 0)
        XCTAssertEqual(score("   ", "Stats"), 0)
    }

    func testTextWithoutTheLettersInOrderDoesNotMatch() {
        XCTAssertNil(score("xyz", "Subdomains"))
        XCTAssertNil(score("sbu", "Subdomains"))
    }

    func testMatchingIgnoresCaseAndAccents() {
        XCTAssertNotNil(score("STATS", "stats"))
        XCTAssertNotNil(score("cafe", "Café"))
    }

    func testAnExactMatchBeatsAPrefix() throws {
        let exact = try XCTUnwrap(score("home", "Home"))
        let prefix = try XCTUnwrap(score("home", "Homebrew"))
        XCTAssertGreaterThan(exact, prefix)
    }

    func testAPrefixBeatsAWordStart() throws {
        let prefix = try XCTUnwrap(score("sub", "Subdomains"))
        let wordStart = try XCTUnwrap(score("sub", "Add subdomain"))
        XCTAssertGreaterThan(prefix, wordStart)
    }

    func testAWordStartBeatsAMatchInsideAWord() throws {
        let wordStart = try XCTUnwrap(score("set", "Open settings"))
        let inside = try XCTUnwrap(score("set", "Reset view"))
        XCTAssertGreaterThan(wordStart, inside)
    }

    func testASubstringBeatsScatteredLetters() throws {
        let substring = try XCTUnwrap(score("dom", "Subdomains"))
        let scattered = try XCTUnwrap(score("dom", "Dropdown menu"))
        XCTAssertGreaterThan(substring, scattered)
    }

    func testWordInitialsBeatScatteredLetters() throws {
        let initials = try XCTUnwrap(score("as", "Add subdomain"))
        let scattered = try XCTUnwrap(score("as", "Stats page"))
        XCTAssertGreaterThan(initials, scattered)
    }

    func testConsecutiveLettersBeatGappedLetters() throws {
        let tight = try XCTUnwrap(score("stt", "stts"))
        let loose = try XCTUnwrap(score("stt", "s-x-t-x-t"))
        XCTAssertGreaterThan(tight, loose)
    }

    func testEveryWordOfTheQueryMustMatchInAnyOrder() throws {
        XCTAssertNotNil(score("claude acme", "New Claude session in acme"))
        XCTAssertNotNil(score("acme claude", "New Claude session in acme"))
        XCTAssertNil(score("claude beta", "New Claude session in acme"))
    }

    func testTheBestFieldWinsAndLaterFieldsCountLess() throws {
        let title = try XCTUnwrap(FuzzyMatch.score("dns", fields: ["DNS", "Subdomains"]))
        let keyword = try XCTUnwrap(FuzzyMatch.score("dns", fields: ["Subdomains", "dns"]))
        XCTAssertGreaterThan(title, keyword)
    }

    func testEachQueryWordMayMatchADifferentField() {
        XCTAssertNotNil(FuzzyMatch.score("stats beta", fields: ["Stats", "beta"]))
        XCTAssertNil(FuzzyMatch.score("stats gamma", fields: ["Stats", "beta"]))
    }
}
