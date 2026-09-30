import XCTest
import SwiftUI
import HarnessUsageKit
@testable import DevmachineApp

@MainActor
final class DMErrorStateTests: XCTestCase {
    func testAFailureGetsAPlainCauseAndKeepsTheExactText() {
        let raw = "ssh: connect to host 203.0.113.10 port 22: Operation timed out\n"
        let state = DMErrorState(title: "Couldn't read acme", message: raw)

        XCTAssertEqual(state.title, "Couldn't read acme")
        XCTAssertEqual(state.cause, "The machine took too long to answer.")
        XCTAssertEqual(state.details, raw)
    }

    func testAnUnknownFailureHasNoCause() {
        let state = DMErrorState(title: "Couldn't load this", message: "exit status 3")
        XCTAssertNil(state.cause)
        XCTAssertEqual(state.details, "exit status 3")
    }

    func testAUsageErrorBecomesAnErrorState() {
        let presentation = HarnessUsageErrorPresentation(
            title: "Codex usage isn't available", cause: "Codex doesn't seem to be signed in.",
            details: "Not logged in", kind: .notSignedIn)
        let state = DMErrorState(presentation)

        XCTAssertEqual(state.title, "Codex usage isn't available")
        XCTAssertEqual(state.cause, "Codex doesn't seem to be signed in.")
        XCTAssertEqual(state.details, "Not logged in")
        XCTAssertEqual(state.systemImage, HarnessUsageErrorKind.notSignedIn.systemImage)
    }

    func testTheDisclosureSaysWhatItDoes() {
        XCTAssertEqual(DMErrorStateView.disclosureTitle(expanded: false), "Show details")
        XCTAssertEqual(DMErrorStateView.disclosureTitle(expanded: true), "Hide details")
        XCTAssertEqual(DMErrorStateView.disclosureValue(expanded: false), "Collapsed")
        XCTAssertEqual(DMErrorStateView.disclosureValue(expanded: true), "Expanded")
    }

    func testTheUsageCardDrawsTheErrorStateInsteadOfTheRawText() throws {
        let raw = "error: not signed in, run `codex login`"
        let recorder = Recorder()
        let card = HarnessUsageCardContent(
            state: HarnessUsageState(harnessID: "codex", errorText: raw),
            title: "Codex Usage", systemImage: "terminal", accent: .purple,
            onRefresh: {}, scrollsContent: false)
            .harnessUsageErrorView { error, retry in
                recorder.seen = error
                return DMErrorStateView(state: DMErrorState(error), retry: retry)
            }
            .frame(width: 380)

        let renderer = ImageRenderer(content: card)
        _ = try XCTUnwrap(renderer.nsImage)

        let seen = try XCTUnwrap(recorder.seen)
        XCTAssertEqual(seen.details, raw)
        XCTAssertEqual(seen.title, "Codex usage isn't available")
        XCTAssertEqual(seen.kind, .notSignedIn)
    }
}

private final class Recorder {
    var seen: HarnessUsageErrorPresentation?
}
