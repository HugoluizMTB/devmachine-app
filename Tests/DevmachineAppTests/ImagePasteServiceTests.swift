import XCTest
import AppKit
@testable import DevmachineApp
@testable import DevmachineCore

private struct RecordingRunner: CommandRunner {
    final class Box: @unchecked Sendable {
        var args: [String] = []
        var input: Data?
    }
    let box = Box()
    let output: String

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        box.args = args
        return output
    }

    func run(executable: String, args: [String], environment: [String: String]?, input: Data)
        throws -> String {
        box.input = input
        return try run(executable: executable, args: args, environment: environment)
    }
}

final class ImagePasteServiceTests: XCTestCase {
    private func png() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    func testARemoteStoreSendsTheBytesAndReturnsThePathTheHostPrinted() throws {
        let runner = RecordingRunner(output: "/home/alice/.claude/image-cache/devmachine-app/a.png\n")
        let service = ImagePasteService(runner: runner)
        let data = png()

        let path = try service.store(
            data, fileExtension: "png", on: .remote(alias: "acme-devmachine", session: "dash"))

        XCTAssertEqual(path, "/home/alice/.claude/image-cache/devmachine-app/a.png")
        XCTAssertEqual(runner.box.input, data)
        XCTAssertTrue(runner.box.args.contains { $0.contains("image-cache/devmachine-app") })
    }

    func testARemoteStoreRefusesAnAnswerThatIsNotAPath() {
        let runner = RecordingRunner(output: "ssh: could not resolve hostname\n")
        let service = ImagePasteService(runner: runner)

        XCTAssertThrowsError(
            try service.store(png(), fileExtension: "png",
                              on: .remote(alias: "acme-devmachine", session: "dash")))
    }

    func testABitmapOnTheClipboardIsReadAsPNG() {
        let board = NSPasteboard(name: NSPasteboard.Name("dm.test.\(UUID().uuidString)"))
        board.clearContents()
        board.setData(png(), forType: .png)

        let image = ImagePasteService.image(from: board)
        XCTAssertEqual(image?.fileExtension, "png")
    }

    func testTextOnTheClipboardIsNotAnImage() {
        let board = NSPasteboard(name: NSPasteboard.Name("dm.test.\(UUID().uuidString)"))
        board.clearContents()
        board.setString("hello", forType: .string)

        XCTAssertNil(ImagePasteService.image(from: board))
    }
}
