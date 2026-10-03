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

    func testAPaneMatchesAHarnessOnlyByItsExactProgram() {
        let out = """
        agy|1
        kimi|1
        pip|1
        cline|1
        @@PANES@@
        agy|agy
        kimi|kimi-code
        pip|pip
        cline|node
        """
        let catalog: [HarnessID: Set<String>] = [
            .pi: ["pi"], .antigravity: ["agy"], .kimi: ["kimi", "kimi-code"], .cline: ["cline", ".cline"]
        ]

        XCTAssertEqual(TmuxListParser.parse(out, processNames: catalog), [
            TmuxSession(name: "agy", windows: 1, harnesses: [.antigravity]),
            TmuxSession(name: "kimi", windows: 1, harnesses: [.kimi]),
            TmuxSession(name: "pip", windows: 1, harnesses: []),
            TmuxSession(name: "cline", windows: 1, harnesses: [])
        ])
    }

    func testAPaneMatchesAHarnessRunningAnywhereUnderIt() {
        let out = """
        cline|1
        pi|1
        shell|1
        @@PANES@@
        cline|node|1000
        pi|pi|2000
        shell|node|3000
        @@PROCS@@
        1000 1 zsh
        1001 1000 node
        1002 1001 .cline
        2000 1 zsh
        2001 2000 pi
        3000 1 zsh
        3001 3000 node
        """
        let catalog: [HarnessID: Set<String>] = [.pi: ["pi"], .cline: ["cline", ".cline"]]

        XCTAssertEqual(TmuxListParser.parse(out, processNames: catalog), [
            TmuxSession(name: "cline", windows: 1, harnesses: [.cline]),
            TmuxSession(name: "pi", windows: 1, harnesses: [.pi]),
            TmuxSession(name: "shell", windows: 1, harnesses: [])
        ])
    }

    func testTheCommandsOwnOrderPutsTheProcessTableBeforeThePanes() {
        let out = """
        cline|1
        @@PROCS@@
         1000     1 bash
         1001  1000 node
         1002  1001 .cline
        @@PANES@@
        cline|node|1000
        """

        XCTAssertEqual(
            TmuxListParser.parse(out, processNames: [.cline: ["cline", ".cline"]]),
            [TmuxSession(name: "cline", windows: 1, harnesses: [.cline])])
    }

    func testAListingCutBeforeThePanesStillListsTheSessions() {
        let out = """
        dash|2
        @@PROCS@@
         1000     1 bash
        """

        XCTAssertEqual(
            TmuxListParser.parse(out, processNames: [.claude: ["claude"]]),
            [TmuxSession(name: "dash", windows: 2, harnesses: [])])
    }

    func testWithoutAProcessTableThePaneCommandStillCounts() {
        let out = """
        cline|1
        pi|1
        @@PANES@@
        cline|node|1000
        pi|pi|2000
        @@PROCS@@
        """
        let catalog: [HarnessID: Set<String>] = [.pi: ["pi"], .cline: ["cline", ".cline"]]

        XCTAssertEqual(TmuxListParser.parse(out, processNames: catalog), [
            TmuxSession(name: "cline", windows: 1, harnesses: []),
            TmuxSession(name: "pi", windows: 1, harnesses: [.pi])
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
