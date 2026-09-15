import XCTest
@testable import DevmachineCore

final class FileSearchTests: XCTestCase {
    private let paths = [
        "Sources/DevmachineApp/AppModel.swift",
        "Sources/DevmachineCore/AppSettings.swift",
        "Tests/DevmachineAppTests/AppModelTests.swift",
        "README.md",
    ]

    func testInitialsFindTheFile() {
        let hits = FileSearch.rank(paths, query: "apmd")
        XCTAssertEqual(hits.first?.path, "Sources/DevmachineApp/AppModel.swift")
    }

    func testLettersThatAreNotThereMatchNothing() {
        XCTAssertNil(FileSearch.score(path: "README.md", query: "zq"))
        // In order means in order: the letters exist but not in this sequence.
        XCTAssertNil(FileSearch.score(path: "README.md", query: "mr"))
    }

    func testTheFileNameBeatsAFolderAbove() {
        let hits = FileSearch.rank(["core/settings/other.swift", "app/AppSettings.swift"],
                                   query: "appsettings")
        XCTAssertEqual(hits.first?.path, "app/AppSettings.swift")
    }

    func testAnEmptyQueryReturnsTheListAsItIs() {
        let hits = FileSearch.rank(paths, query: "   ", limit: 2)
        XCTAssertEqual(hits.map(\.path), Array(paths.prefix(2)))
    }

    func testTheShorterPathWinsATie() {
        let hits = FileSearch.rank(["a/b/model.swift", "model.swift"], query: "model")
        XCTAssertEqual(hits.first?.path, "model.swift")
    }

    func testTheLimitIsHonoured() {
        XCTAssertEqual(FileSearch.rank(paths, query: "s", limit: 2).count, 2)
    }
}

final class ListFilesCommandTests: XCTestCase {
    func testAsksGitFirstAndFallsBackToAWalk() {
        let command = RemoteCommands.listFiles(root: "~/dev/acme", limit: 10)
        XCTAssertTrue(command.contains("cd \"$HOME\"/'dev/acme'"))
        XCTAssertTrue(command.contains("git ls-files"))
        XCTAssertTrue(command.contains("-not -path '*/node_modules/*'"))
        XCTAssertTrue(command.hasSuffix("head -n 10"))
    }

    func testTypingDoesNotSend() {
        let command = RemoteCommands.typeKeys(session: "main", text: "src/a.swift")
        XCTAssertFalse(command.hasSuffix("Enter"))
        XCTAssertTrue(command.contains("'src/a.swift'"))
    }
}
