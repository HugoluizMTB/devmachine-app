import XCTest
@testable import DevmachineCore

final class FilePreviewTests: XCTestCase {
    private func output(_ bytes: Int, _ data: Data) -> String {
        "\(bytes)\u{1e}" + data.base64EncodedString()
    }

    private func output(_ text: String) -> String {
        let data = Data(text.utf8)
        return output(data.count, data)
    }

    func testTheCommandAsksForTheSizeAndTheBytes() {
        let command = FilePreviewReader.command(path: "/tmp/a file.swift", limit: 100)
        XCTAssertTrue(command.contains("wc -c < '/tmp/a file.swift'"))
        XCTAssertTrue(command.contains("head -c 100 -- '/tmp/a file.swift'"))
        XCTAssertTrue(command.contains("base64 | tr -d '\\n'"))
    }

    func testCodeCarriesItsLanguage() throws {
        let preview = try XCTUnwrap(
            FilePreviewReader.parse(output("print(1)\n"), path: "/repo/main.swift"))
        XCTAssertEqual(preview.kind, .code(language: "swift"))
        XCTAssertEqual(preview.text, "print(1)\n")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.name, "main.swift")
    }

    func testMarkdownIsItsOwnKind() throws {
        let preview = try XCTUnwrap(
            FilePreviewReader.parse(output("# Title\n"), path: "/repo/README.md"))
        XCTAssertEqual(preview.kind, .markdown)
    }

    func testAnUnknownExtensionIsPlainText() throws {
        let preview = try XCTUnwrap(
            FilePreviewReader.parse(output("hello"), path: "/repo/notes.whatever"))
        XCTAssertEqual(preview.kind, .text)
    }

    func testAFileNamedAfterAToolIsRecognised() {
        XCTAssertEqual(FilePreviewReader.language(for: "/repo/Dockerfile"), "dockerfile")
        XCTAssertEqual(FilePreviewReader.language(for: "/repo/Gemfile"), "ruby")
        XCTAssertNil(FilePreviewReader.language(for: "/repo/LICENSE"))
    }

    func testANulByteMeansBinary() throws {
        let data = Data([0x7f, 0x45, 0x4c, 0x46, 0x00, 0x01])
        let preview = try XCTUnwrap(
            FilePreviewReader.parse(output(data.count, data), path: "/usr/bin/tool"))
        XCTAssertEqual(preview.kind, .binary)
        XCTAssertNil(preview.text)
    }

    func testAnImageKeepsItsBytes() throws {
        let data = Data([0x89, 0x50, 0x4e, 0x47])
        let preview = try XCTUnwrap(
            FilePreviewReader.parse(output(data.count, data), path: "/repo/logo.png"))
        XCTAssertEqual(preview.kind, .image)
        XCTAssertEqual(preview.data, data)
    }

    func testAnImageTooBigIsRefusedInsteadOfShown() throws {
        let data = Data([0x89, 0x50])
        let preview = try XCTUnwrap(FilePreviewReader.parse(
            output(FilePreviewReader.imageLimit + 1, data), path: "/repo/huge.png"))
        XCTAssertEqual(preview.kind, .tooLarge(bytes: FilePreviewReader.imageLimit + 1))
    }

    func testAReadThatStoppedShortSaysSo() throws {
        let data = Data("abc".utf8)
        let preview = try XCTUnwrap(
            FilePreviewReader.parse(output(9_999, data), path: "/repo/big.txt"))
        XCTAssertTrue(preview.isTruncated)
        XCTAssertEqual(preview.byteCount, 9_999)
    }

    func testTextTooLongToHighlightStaysPlain() throws {
        let long = String(repeating: "a", count: FilePreviewReader.highlightLimit + 1)
        let preview = try XCTUnwrap(
            FilePreviewReader.parse(output(long), path: "/repo/generated.swift"))
        XCTAssertEqual(preview.kind, .text)
    }

    func testOutputThatIsNotTheCommandsShapeIsRefused() {
        XCTAssertNil(FilePreviewReader.parse("", path: "/repo/a.swift"))
        XCTAssertNil(FilePreviewReader.parse("no separator", path: "/repo/a.swift"))
        XCTAssertNil(FilePreviewReader.parse("12\u{1e}!!!not base64!!!", path: "/repo/a.swift"))
    }
}
