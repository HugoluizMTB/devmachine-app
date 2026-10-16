import XCTest
@testable import DevmachineCore

final class ChatFailurePresentationTests: XCTestCase {
    private func card(_ kind: ChatFailureKind, harness: HarnessID = .claude, place: ChatPlace = .workspace("main"))
        -> ChatFailurePresentation {
        ChatFailurePresentation(failure: ChatFailure(kind: kind, message: "x"), harness: harness, place: place)
    }

    func testLoggedOutOffersLogInAndAnotherWorkspace() {
        let presentation = card(.harnessLoggedOut)
        XCTAssertEqual(presentation.title, "Claude is not logged in on main")
        XCTAssertTrue(presentation.body.hasPrefix("The claude CLI on main has no login"))
        XCTAssertEqual(presentation.actions, [.logIn, .chooseAnotherWorkspace])
        XCTAssertEqual(card(.harnessLoggedOut, place: .local).title, "Claude is not logged in on this Mac")
    }

    func testMissingHarnessNamesThePackage() {
        let presentation = card(.harnessMissing, harness: .codex, place: .workspace("acme"))
        XCTAssertEqual(presentation.title, "Codex is not installed on acme")
        XCTAssertTrue(presentation.body.contains("the codex package"))
        XCTAssertEqual(presentation.actions, [.openPackages, .chooseAnotherWorkspace, .tryAgain])
        XCTAssertFalse(card(.harnessMissing, place: .local).actions.contains(.openPackages))
    }

    func testAnOlderCLIOffersTheUpdate() {
        XCTAssertEqual(card(.needsNewerCLI).actions.first, .updateCLI)
    }

    func testEveryKindHasATitleAndAWayOn() {
        let kinds: [ChatFailureKind] = [
            .unreachable, .loginRefused, .hostKeyRejected, .harnessFailed, .sessionNotFound, .transcriptNotFound,
            .other("cli-not-found"), .other("new-kind"),
        ]
        for kind in kinds {
            XCTAssertFalse(card(kind).title.isEmpty, "\(kind)")
            XCTAssertFalse(card(kind).actions.isEmpty, "\(kind)")
        }
    }
}
