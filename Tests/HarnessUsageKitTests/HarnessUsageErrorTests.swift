import XCTest
@testable import HarnessUsageKit

final class HarnessUsageErrorTests: XCTestCase {
    func testTypedErrorsMapToTheirKind() {
        XCTAssertEqual(HarnessUsageErrorKind(error: CodexTransportError.executableUnavailable), .cliNotFound)
        XCTAssertEqual(HarnessUsageErrorKind(error: UsageProviderError.executableNotFound("claude")), .cliNotFound)
        XCTAssertEqual(HarnessUsageErrorKind(error: CodexTransportError.timedOut), .timedOut)
        XCTAssertEqual(HarnessUsageErrorKind(error: UsageProviderError.timedOut), .timedOut)
        XCTAssertEqual(HarnessUsageErrorKind(error: CodexTransportError.malformedResponse), .unreadable)
        XCTAssertEqual(HarnessUsageErrorKind(error: CodexTransportError.missingResponse(id: 2)), .unreadable)
        XCTAssertEqual(HarnessUsageErrorKind(error: UsageProviderError.decodeFailed), .unreadable)
    }

    func testMessagesInsideFailuresAreRead() {
        XCTAssertEqual(
            HarnessUsageErrorKind(error: CodexTransportError.rpcError(code: -32600, message: "Not logged in")),
            .notSignedIn)
        XCTAssertEqual(
            HarnessUsageErrorKind(error: CodexTransportError.processFailed(status: 1, stderr: "boom")),
            .unknown)
    }

    func testTextIsClassified() {
        XCTAssertEqual(HarnessUsageErrorKind(text: "error: not signed in, run `codex login`"), .notSignedIn)
        XCTAssertEqual(HarnessUsageErrorKind(text: "401 Unauthorized"), .notSignedIn)
        XCTAssertEqual(HarnessUsageErrorKind(text: "Codex CLI is unavailable"), .cliNotFound)
        XCTAssertEqual(HarnessUsageErrorKind(text: "The file “codex” doesn’t exist."), .cliNotFound)
        XCTAssertEqual(HarnessUsageErrorKind(text: "Codex account usage timed out"), .timedOut)
        XCTAssertEqual(HarnessUsageErrorKind(text: "Codex returned malformed account usage"), .unreadable)
        XCTAssertEqual(HarnessUsageErrorKind(text: "something odd"), .unknown)
    }

    func testEveryKnownKindNamesALikelyCause() {
        XCTAssertEqual(HarnessUsageErrorKind.notSignedIn.cause(tool: "Codex"), "Codex doesn't seem to be signed in.")
        XCTAssertEqual(HarnessUsageErrorKind.cliNotFound.cause(tool: "Codex"), "The Codex CLI wasn't found on this Mac.")
        XCTAssertEqual(HarnessUsageErrorKind.timedOut.cause(tool: "Codex"), "Codex took too long to answer.")
        XCTAssertEqual(HarnessUsageErrorKind.unreadable.cause(tool: "Codex"), "Codex sent back usage that couldn't be read.")
        XCTAssertNil(HarnessUsageErrorKind.unknown.cause(tool: "Codex"))
    }

    func testStateDerivesTheKindFromItsTextWhenNoneIsGiven() {
        let state = HarnessUsageState(harnessID: "codex", errorText: "Not logged in")
        XCTAssertEqual(state.errorKind, .notSignedIn)
        XCTAssertNil(HarnessUsageState(harnessID: "codex").errorKind)
    }

    func testPresentationKeepsTheExactErrorText() throws {
        let raw = "  line one\n\tline two: {\"code\": 401}  "
        let state = HarnessUsageState(harnessID: "codex", errorText: raw, errorKind: .notSignedIn)
        let error = try XCTUnwrap(HarnessUsagePresentation(title: "Codex Usage", state: state).error)

        XCTAssertEqual(error.title, "Codex usage isn't available")
        XCTAssertEqual(error.cause, "Codex doesn't seem to be signed in.")
        XCTAssertEqual(error.details, raw)
        XCTAssertEqual(error.kind, .notSignedIn)
    }

    func testPresentationWithoutAUsageSuffixUsesTheWholeTitle() throws {
        let state = HarnessUsageState(harnessID: "tool", errorText: "offline")
        let error = try XCTUnwrap(HarnessUsagePresentation(title: "Tool", state: state).error)
        XCTAssertEqual(error.title, "Tool usage isn't available")
        XCTAssertNil(error.cause)
    }

    func testNoErrorMeansNoErrorPresentation() {
        let state = HarnessUsageState(harnessID: "codex", snapshot: .init())
        XCTAssertNil(HarnessUsagePresentation(title: "Codex Usage", state: state).error)
    }

    @MainActor
    func testTheStoreRecordsTheKindOfAFailure() async throws {
        let store = HarnessUsageStore(providers: [FailingProvider()])
        store.refresh(force: true)
        for _ in 0..<100 where store.states[0].errorText == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(store.states[0].errorKind, .cliNotFound)
        XCTAssertEqual(store.states[0].errorText, "Codex CLI is unavailable")
    }
}

private struct FailingProvider: HarnessUsageProvider {
    let harnessID = "codex"
    func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot {
        throw CodexTransportError.executableUnavailable
    }
}
