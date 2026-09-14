import XCTest
@testable import DevmachineCore

final class FileTreeParserTests: XCTestCase {
    func testDirectoriesComeFirstThenFilesCaseInsensitive() {
        let output = """
        f\tREADME.md
        d\tTests
        f\tPackage.swift
        d\tsources
        """

        let entries = FileTreeParser.parse(output)

        XCTAssertEqual(entries.map(\.name), ["sources", "Tests", "Package.swift", "README.md"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, true, false, false])
    }

    func testEveryTypeMapsToAKind() {
        let output = "d\tdev\nf\tnotes.md\nl\tcurrent\np\tfifo\n"

        let kinds = Dictionary(
            uniqueKeysWithValues: FileTreeParser.parse(output).map { ($0.name, $0.kind) }
        )

        XCTAssertEqual(kinds["dev"], .directory)
        XCTAssertEqual(kinds["notes.md"], .file)
        XCTAssertEqual(kinds["current"], .symlink)
        XCTAssertEqual(kinds["fifo"], .other)
    }

    func testGitIsHiddenButOtherDotfilesAreKept() {
        let output = "d\t.git\nd\t.build\nf\t.gitignore\n"

        XCTAssertEqual(FileTreeParser.parse(output).map(\.name), [".build", ".gitignore"])
    }

    func testANameWithATabKeepsEverythingAfterTheFirstOne() {
        XCTAssertEqual(
            FileTreeParser.parse("f\tweird\tname.txt").map(\.name),
            ["weird\tname.txt"]
        )
    }

    func testBrokenLinesAreDropped() {
        XCTAssertTrue(FileTreeParser.parse("no tab here\ndd\ttwo letters\nf\t\n\n").isEmpty)
    }

    func testEmptyOutputIsAnEmptyListing() {
        XCTAssertTrue(FileTreeParser.parse("").isEmpty)
    }

    func testFileTreeRootFallsBackToThePaneDirectory() {
        let command = RemoteCommands.fileTreeRoot(session: "dash")

        XCTAssertEqual(
            command,
            "cd \"$(tmux display -p -t 'dash' '#{pane_current_path}')\""
                + " && (git rev-parse --show-toplevel 2>/dev/null || pwd)"
        )
    }

    func testFileTreeRootEscapesTheSessionName() {
        XCTAssertTrue(RemoteCommands.fileTreeRoot(session: "x'y").contains("-t 'x'\\''y'"))
    }

    func testListDirectoryAsksFindForTypeAndNameOnly() {
        XCTAssertEqual(
            RemoteCommands.listDirectory(path: "/home/alice/dev/dash"),
            "find '/home/alice/dev/dash' -mindepth 1 -maxdepth 1 -printf '%y\\t%f\\n' | sort -f"
        )
    }

    func testListDirectoryIsInjectionSafe() {
        XCTAssertEqual(
            RemoteCommands.listDirectory(path: "/home/alice/a b; rm -rf /"),
            "find '/home/alice/a b; rm -rf /' -mindepth 1 -maxdepth 1 -printf '%y\\t%f\\n' | sort -f"
        )
        XCTAssertTrue(RemoteCommands.listDirectory(path: "x'y").contains("'x'\\''y'"))
    }
}
