import XCTest
@testable import DevmachineCore

final class FileListParserTests: XCTestCase {
    func testParsesDirsFirstThenFilesAlphabetically() {
        let output = "dir1/\nfile.txt\n.hidden/\n./\n../\nzeta/\nalpha.md\n"

        let entries = FileListParser.parse(output)

        XCTAssertEqual(entries, [
            FileEntry(name: ".hidden", isDir: true),
            FileEntry(name: "dir1", isDir: true),
            FileEntry(name: "zeta", isDir: true),
            FileEntry(name: "alpha.md", isDir: false),
            FileEntry(name: "file.txt", isDir: false)
        ])
    }

    func testSkipsEmptyLines() {
        let output = "dir1/\n\n\nfile.txt\n"

        let entries = FileListParser.parse(output)

        XCTAssertEqual(entries, [
            FileEntry(name: "dir1", isDir: true),
            FileEntry(name: "file.txt", isDir: false)
        ])
    }

    func testEmptyOutputProducesEmptyList() {
        XCTAssertEqual(FileListParser.parse(""), [])
        XCTAssertEqual(FileListParser.parse("./\n../\n"), [])
    }

    func testPreservesTrailingSpaceInFileName() {
        let output = "notes \nfile.txt\n"

        let entries = FileListParser.parse(output)

        XCTAssertTrue(entries.contains(FileEntry(name: "notes ", isDir: false)))
    }
}
