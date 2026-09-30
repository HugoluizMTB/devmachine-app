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

    func run(
        executable: String, args: [String], environment: [String: String]?, input: Data,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> String {
        box.input = input
        onBytesWritten?(input.count)
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
        let service = ImagePasteService(
            runner: runner,
            storagePolicy: ImageStoragePolicy(directory: ".claude/image-cache/devmachine-app"))
        let data = png()

        let path = try service.store(
            data, fileExtension: "png", on: .remote(alias: "acme-devmachine", session: "dash"))

        XCTAssertEqual(path, "/home/alice/.claude/image-cache/devmachine-app/a.png")
        XCTAssertEqual(runner.box.input, data)
        XCTAssertTrue(runner.box.args.contains { $0.contains("image-cache/devmachine-app") })
    }

    func testARemoteStoreRefusesAnAnswerThatIsNotAPath() {
        let runner = RecordingRunner(output: "ssh: could not resolve hostname\n")
        let service = ImagePasteService(runner: runner, storagePolicy: .appManaged)

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

    @MainActor
    func testTheLabelNamesTheWorkspaceTheImageGoesTo() {
        XCTAssertEqual(
            TerminalRegistry.sendingLabel(for: .remote(alias: "acme-devmachine", session: "dash")),
            "Sending image to acme-devmachine\u{2026}")
        XCTAssertEqual(
            TerminalRegistry.sendingLabel(for: .local(session: "Operator", path: "/tmp")),
            "Saving image\u{2026}")
    }

    @MainActor
    func testAFileSentFromThePaletteIsCalledAFile() {
        XCTAssertEqual(
            TerminalRegistry.sendingLabel(
                for: .remote(alias: "acme-devmachine", session: "dash"), noun: "file"),
            "Sending file to acme-devmachine\u{2026}")
    }

    func testStoringReportsEveryByte() throws {
        let runner = RecordingRunner(output: "/home/alice/a.png\n")
        let service = ImagePasteService(runner: runner, storagePolicy: .appManaged)
        let data = png()
        final class Seen: @unchecked Sendable { var last = 0 }
        let seen = Seen()

        _ = try service.store(
            data, fileExtension: "png",
            on: .remote(alias: "acme-devmachine", session: "dash"),
            onBytesWritten: { seen.last = $0 })

        XCTAssertEqual(seen.last, data.count)
        XCTAssertTrue(runner.box.args.contains { $0.contains(".cache/devmachine-app/images") })
    }
}
