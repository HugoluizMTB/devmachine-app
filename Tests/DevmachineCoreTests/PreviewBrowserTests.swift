import XCTest
@testable import DevmachineCore

final class DocumentSplitTests: XCTestCase {
    func testTheDefaultSplitIsHalfAndHalf() {
        XCTAssertEqual(DocumentSplit.defaultFraction, 0.5)
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 0.5, available: 1400), 700)
    }

    func testThePreviewCanTakeAllButTheTerminalsMinimum() {
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 0.95, available: 2000), 1680)
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 1, available: 2000), 2000 - DocumentSplit.minimumSide)
    }

    func testThereIsNoFixedCapOnAWideWindow() {
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 0.75, available: 4000), 3000)
    }

    func testThePreviewNeverShrinksBelowItsMinimum() {
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 0.05, available: 1400), DocumentSplit.minimumSide)
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 0, available: 1400), 320)
    }

    func testANarrowWindowSplitsInHalf() {
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 0.9, available: 500), 250)
        XCTAssertEqual(DocumentSplit.trailingWidth(fraction: 0.5, available: 0), 0)
    }

    func testADraggedWidthBecomesAClampedFraction() {
        XCTAssertEqual(DocumentSplit.fraction(forTrailingWidth: 700, available: 1400), 0.5)
        XCTAssertEqual(DocumentSplit.fraction(forTrailingWidth: 5000, available: 1400), 1080.0 / 1400.0)
        XCTAssertEqual(DocumentSplit.fraction(forTrailingWidth: -40, available: 1400), 320.0 / 1400.0)
    }

    func testAFractionFromANarrowWindowIsHalf() {
        XCTAssertEqual(DocumentSplit.fraction(forTrailingWidth: 400, available: 500), 0.5)
        XCTAssertEqual(DocumentSplit.fraction(forTrailingWidth: 400, available: 0), 0.5)
    }

    func testAStoredFractionIsKeptOnlyWhenValid() {
        XCTAssertEqual(DocumentSplit.stored(0.7), 0.7)
        XCTAssertEqual(DocumentSplit.stored(nil), 0.5)
        XCTAssertEqual(DocumentSplit.stored(0), 0.5)
        XCTAssertEqual(DocumentSplit.stored(1.2), 0.5)
        XCTAssertEqual(DocumentSplit.stored(.nan), 0.5)
    }
}

final class PreviewTitleTests: XCTestCase {
    func testThePageTitleWins() {
        XCTAssertEqual(
            PreviewTitle.display(pageTitle: "Acme Docs", url: URL(string: "https://docs.example.com/a"), fallback: "x"),
            "Acme Docs")
    }

    func testABlankTitleFallsBackToTheCurrentHost() {
        XCTAssertEqual(
            PreviewTitle.display(pageTitle: "  \n", url: URL(string: "https://www.example.net/search"), fallback: "example.com"),
            "www.example.net")
        XCTAssertEqual(
            PreviewTitle.display(pageTitle: nil, url: URL(string: "https://www.example.net"), fallback: "example.com"),
            "www.example.net")
    }

    func testAHostKeepsAnExplicitPort() {
        XCTAssertEqual(
            PreviewTitle.display(pageTitle: nil, url: URL(string: "http://localhost:5173/admin"), fallback: "acme:5173"),
            "localhost:5173")
    }

    func testNoTitleAndNoHostKeepsTheFallback() {
        XCTAssertEqual(PreviewTitle.display(pageTitle: nil, url: nil, fallback: "acme:3000"), "acme:3000")
        XCTAssertEqual(PreviewTitle.display(pageTitle: "", url: URL(string: "about:blank"), fallback: "acme:3000"), "acme:3000")
    }

    func testTheTitleIsTrimmedAndKeptOnOneLine() {
        XCTAssertEqual(
            PreviewTitle.display(pageTitle: "  Acme\n  Dashboard ", url: nil, fallback: "x"), "Acme Dashboard")
    }
}

final class SafariUserAgentTests: XCTestCase {
    func testTheApplicationNameReadsLikeSafari() {
        XCTAssertEqual(
            SafariUserAgent.applicationName(safariVersion: "26.5", osVersion: .init(majorVersion: 15, minorVersion: 7, patchVersion: 7)),
            "Version/26.5 Safari/605.1.15")
    }

    func testWithoutSafariTheVersionFollowsTheSystem() {
        XCTAssertEqual(
            SafariUserAgent.applicationName(safariVersion: nil, osVersion: .init(majorVersion: 26, minorVersion: 1, patchVersion: 0)),
            "Version/26.1 Safari/605.1.15")
        XCTAssertEqual(
            SafariUserAgent.applicationName(safariVersion: "", osVersion: .init(majorVersion: 15, minorVersion: 6, patchVersion: 1)),
            "Version/18.6 Safari/605.1.15")
        XCTAssertEqual(
            SafariUserAgent.applicationName(safariVersion: "not a version", osVersion: .init(majorVersion: 14, minorVersion: 0, patchVersion: 0)),
            "Version/17.0 Safari/605.1.15")
    }

    func testTheFullStringMatchesSafarisShape() {
        let agent = SafariUserAgent.full(applicationName: "Version/26.5 Safari/605.1.15")
        XCTAssertEqual(
            agent,
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15")
    }
}

final class DocumentSplitDragTests: XCTestCase {
    func testDraggingLeftGrowsThePane() {
        XCTAssertEqual(DocumentSplit.dragged(from: 0.5, by: -200, available: 2000), 0.6, accuracy: 0.0001)
    }

    func testDraggingRightShrinksThePane() {
        XCTAssertEqual(DocumentSplit.dragged(from: 0.5, by: 300, available: 2000), 0.35, accuracy: 0.0001)
    }

    func testADragPastEitherEdgeStopsAtTheMinimum() {
        XCTAssertEqual(DocumentSplit.dragged(from: 0.5, by: -5000, available: 2000), 1680.0 / 2000.0)
        XCTAssertEqual(DocumentSplit.dragged(from: 0.5, by: 5000, available: 2000), 320.0 / 2000.0)
    }
}
