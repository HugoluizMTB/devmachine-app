import XCTest
@testable import DevmachineCore

final class HarnessPromptTests: XCTestCase {
    func testClaudeAndCodexTakeTheFirstMessageAsAnArgument() {
        XCTAssertEqual(
            HarnessPrompt.command("claude", harness: .claude, prompt: HarnessPrompt.operatorIntro),
            "claude 'Explain to me what I can do here.'")
        XCTAssertEqual(
            HarnessPrompt.command("codex", harness: .codex, prompt: HarnessPrompt.operatorIntro),
            "codex 'Explain to me what I can do here.'")
    }

    func testAnyOtherHarnessHasNoKnownPromptArgument() {
        for id in [HarnessID.pi, .opencode, .kimi, .antigravity, .cline] {
            XCTAssertNil(HarnessPrompt.command(id.rawValue, harness: id, prompt: "hello"))
        }
    }

    func testThePromptIsQuotedForTheShell() {
        XCTAssertEqual(
            HarnessPrompt.command("claude", harness: .claude, prompt: "what's $HOME; rm -rf `x`"),
            #"claude 'what'\''s $HOME; rm -rf `x`'"#)
        XCTAssertEqual(HarnessPrompt.shellQuoted("plain"), "'plain'")
    }
}
