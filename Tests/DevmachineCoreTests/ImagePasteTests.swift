import XCTest
@testable import DevmachineCore

final class ImagePasteTests: XCTestCase {
    func testFileNameCarriesTheTimeAndATail() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            ImagePaste.fileName(date: date, fileExtension: "png", tail: "a1b2"),
            "20231114-221320-a1b2.png")
    }

    func testTheCommandWritesUnderTheHomeAndPrintsTheAbsolutePath() {
        let command = ImagePaste.writeCommand(fileName: "shot.png")
        XCTAssertTrue(command.contains("mkdir -p \"$HOME\"/.claude/image-cache/devmachine-app"))
        XCTAssertTrue(command.contains("cat > \"$HOME\"/.claude/image-cache/devmachine-app/'shot.png'"))
        XCTAssertTrue(command.hasSuffix("printf '%s\\n' \"$HOME\"/.claude/image-cache/devmachine-app/'shot.png'"))
    }

    func testAQuoteInTheNameCannotEndTheQuoting() {
        let command = ImagePaste.writeCommand(fileName: "a'b.png")
        XCTAssertTrue(command.contains("'a'\\''b.png'"))
    }
}
