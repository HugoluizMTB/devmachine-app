import XCTest
@testable import DevmachineCore

final class TmuxListParserTests: XCTestCase {
    private let catalog: [HarnessID: Set<String>] = [
        .claude: ["claude"],
        .codex: ["codex"]
    ]

    func testParsesSessionsAndDetectsEveryRecognizedHarness() {
        let out = """
        dash-agents|3
        dash-codex|2
        dash-shell|1
        @@PANES@@
        dash-agents|claude
        dash-agents|codex
        dash-agents|zsh
        dash-codex|codex
        dash-shell|zsh
        """
        let sessions = TmuxListParser.parse(out, processNames: catalog)

        XCTAssertEqual(sessions, [
            TmuxSession(name: "dash-agents", windows: 3, harnesses: [.claude, .codex]),
            TmuxSession(name: "dash-codex", windows: 2, harnesses: [.codex]),
            TmuxSession(name: "dash-shell", windows: 1, harnesses: [])
        ])
    }

    func testIgnoresUnknownCommands() {
        let out = """
        dash|1
        @@PANES@@
        dash|aider
        dash|zsh
        """

        XCTAssertEqual(
            TmuxListParser.parse(out, processNames: catalog),
            [TmuxSession(name: "dash", windows: 1, harnesses: [])]
        )
    }

    func testOnlyProgramsInTheSuppliedCatalogAreDetected() {
        let out = """
        dash|1
        @@PANES@@
        dash|claude
        dash|codex
        """

        XCTAssertEqual(
            TmuxListParser.parse(out, processNames: [.codex: ["codex"]]),
            [TmuxSession(name: "dash", windows: 1, harnesses: [.codex])]
        )
    }

    func testEmptyOutputWhenNoServerRunning() {
        XCTAssertEqual(TmuxListParser.parse("@@PANES@@\n", processNames: catalog), [])
        XCTAssertEqual(TmuxListParser.parse("", processNames: catalog), [])
    }
}
