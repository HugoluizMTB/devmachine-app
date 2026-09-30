import XCTest
@testable import DevmachineCore

final class CustomSessionCommandTests: XCTestCase {
    func testNormalizedTrimsSurroundingWhitespace() {
        XCTAssertEqual(CustomSessionCommand.normalized("  npm run dev \n"), "npm run dev")
    }

    func testNormalizedRejectsEmptyAndBlankInput() {
        XCTAssertNil(CustomSessionCommand.normalized(""))
        XCTAssertNil(CustomSessionCommand.normalized("   \t\n"))
    }

    func testNormalizedJoinsLinesSoOneReturnRunsTheWholeCommand() {
        XCTAssertEqual(CustomSessionCommand.normalized("npm install\nnpm run dev"), "npm install npm run dev")
    }

    func testNormalizedKeepsInnerQuotesAndSymbolsUntouched() {
        let raw = #"claude --model opus -p "fix it" && echo '$HOME' | tee ~/log; `date`"#
        XCTAssertEqual(CustomSessionCommand.normalized(raw), raw)
    }

    func testRemoteLaunchTypesTheCommandLiterallyAndThenPressesEnter() {
        XCTAssertEqual(
            RemoteCommands.sendKeys(session: "dash", text: "claude --model opus"),
            "tmux send-keys -t 'dash' -l -- 'claude --model opus' \\; send-keys -t 'dash' Enter")
    }

    func testRemoteLaunchQuotesEveryShellCharacterSoTheTextArrivesVerbatim() {
        let typed = #"echo 'it'"s" $HOME; `whoami` | cat && ls *"#
        let command = RemoteCommands.sendKeys(session: "dash", text: typed)

        XCTAssertEqual(unquotedLiteral(in: command), typed)
    }

    func testRemoteLaunchDoesNotLetTmuxReadATypedWordAsAKeyName() {
        XCTAssertTrue(RemoteCommands.sendKeys(session: "dash", text: "Enter").contains(" -l -- 'Enter' "))
    }

    func testLocalLaunchPassesTheTypedTextAsOneArgument() {
        let typed = #"npm run dev -- --port "3000""#
        XCTAssertEqual(Zmx.sendArguments(name: "acme", text: typed), ["send", "acme", typed])
    }

    private func unquotedLiteral(in command: String) -> String? {
        guard let start = command.range(of: " -l -- '"),
              let end = command.range(of: "' \\; send-keys", options: .backwards) else { return nil }
        return String(command[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "'\\''", with: "'")
    }
}

final class RecentCommandsTests: XCTestCase {
    func testRecordingPutsTheNewestFirst() {
        XCTAssertEqual(RecentCommands.recording("htop", in: ["npm run dev"]), ["htop", "npm run dev"])
    }

    func testRecordingARepeatMovesItToTheTopInsteadOfDuplicatingIt() {
        XCTAssertEqual(
            RecentCommands.recording("npm run dev", in: ["htop", "npm run dev", "top"]),
            ["npm run dev", "htop", "top"])
    }

    func testRecordingDropsTheOldestPastTheCap() {
        let full = (1...RecentCommands.capacity).map { "cmd \($0)" }

        let result = RecentCommands.recording("new", in: full)

        XCTAssertEqual(result.count, RecentCommands.capacity)
        XCTAssertEqual(result.first, "new")
        XCTAssertFalse(result.contains("cmd \(RecentCommands.capacity)"))
    }

    func testMergedKeepsOrderDedupesAndCaps() {
        let merged = RecentCommands.merged([["a", "b"], ["b", "c", "d", "e", "f", "g", "h", "i", "j"]])

        XCTAssertEqual(merged.first, "a")
        XCTAssertEqual(merged.filter { $0 == "b" }.count, 1)
        XCTAssertEqual(merged.count, RecentCommands.capacity)
    }
}
