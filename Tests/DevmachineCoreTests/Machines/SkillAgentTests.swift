import XCTest
@testable import DevmachineCore

final class SkillAgentTests: XCTestCase {
    private let everyHarness: [(id: HarnessID, title: String)] = [
        (.claude, "Claude Code"), (.codex, "OpenAI Codex"), (.pi, "Pi"), (.antigravity, "Antigravity CLI"),
        (.opencode, "opencode"), (.kimi, "Kimi Code"), (.cline, "Cline"),
    ]

    func testEveryHarnessIsOfferedUnderItsCLIAgentNameOnACLIThatTakesThemAll() {
        let options = SkillAgent.options(
            harnesses: everyHarness, cliVersion: SemanticVersion(major: 0, minor: 7, patch: 28))
        XCTAssertEqual(options.map(\.id), ["claude", "codex", "pi", "antigravity", "opencode", "kimi", "cline"])
        XCTAssertEqual(options.map(\.name), everyHarness.map(\.title))
    }

    func testAnOlderOrUnreadCLIIsOfferedOnlyTheAgentsItAccepts() {
        for version in [SemanticVersion(major: 0, minor: 7, patch: 27), nil] {
            let options = SkillAgent.options(harnesses: everyHarness, cliVersion: version)
            XCTAssertEqual(options.map(\.id), ["claude", "codex", "pi", "opencode"])
        }
    }

    func testAHarnessTheCLICannotLinkIsNotOffered() {
        let options = SkillAgent.options(
            harnesses: [(HarnessID(rawValue: "aider"), "Aider"), (.claude, "Claude Code")], cliVersion: nil)
        XCTAssertEqual(options.map(\.id), ["claude"])
    }

    func testPreselectedAreTheEnabledHarnessesAndTheOnesWhoseFolderThisHomeHas() {
        let options = SkillAgent.options(
            harnesses: everyHarness, cliVersion: SemanticVersion(major: 0, minor: 7, patch: 28))
        let folders: Set = ["/Users/alice/.kimi-code", "/Users/alice/.gemini/antigravity-cli"]
        let chosen = SkillAgent.preselected(
            from: options, harnesses: [.cline, .claude], home: "/Users/alice", isDirectory: folders.contains)
        XCTAssertEqual(chosen.map(\.id), ["claude", "antigravity", "kimi", "cline"])
    }
}
