import XCTest
import AppKit
@testable import DevmachineApp
@testable import DevmachineCore

private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    var args: [[String]] = []
    var inputs: [Data] = []
    let answer: ([String]) -> (stdout: String, stderr: String, exitCode: Int32)

    init(answer: @escaping ([String]) -> (stdout: String, stderr: String, exitCode: Int32)) {
        self.answer = answer
    }

    convenience init(output: String) {
        self.init { _ in (output, "", 0) }
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        self.args.append(args)
        return answer(args).stdout
    }

    func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        self.args.append(args)
        if let input {
            inputs.append(input)
            onBytesWritten?(input.count)
        }
        return answer(args)
    }
}

final class FileUploadServiceTests: XCTestCase {
    private let remote = TerminalKind.remote(alias: "acme-devmachine", session: "dash")
    private let shot = UploadName(stem: "shot-20260930-143012", ext: ".png")

    private func png() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    func testARemoteStoreSendsTheBytesAndReturnsThePathTheHostPrinted() throws {
        let runner = RecordingRunner(
            output: "/home/alice/.claude/image-cache/devmachine-app/shot-20260930-143012.png\n")
        let service = FileUploadService(
            runner: runner,
            storagePolicy: UploadStoragePolicy(directory: ".claude/image-cache/devmachine-app"))
        let data = png()

        let path = try service.store(
            data, name: shot, on: remote)

        XCTAssertEqual(path, "/home/alice/.claude/image-cache/devmachine-app/shot-20260930-143012.png")
        XCTAssertEqual(runner.inputs, [data])
        XCTAssertTrue(runner.args[0].last?.contains("image-cache/devmachine-app") == true)
        XCTAssertTrue(runner.args[0].contains("acme-devmachine"))
    }

    func testARemoteStoreRefusesAnAnswerThatIsNotThePath() {
        let runner = RecordingRunner { _ in ("", "ssh: Could not resolve hostname", 255) }
        let service = FileUploadService(runner: runner, storagePolicy: .appManaged)

        XCTAssertThrowsError(
            try service.store(png(), name: shot, on: remote)
        ) { error in
            guard case let .transferFailed(details)? = error as? FileUploadService.Failure else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(details.contains("Could not resolve hostname"))
        }
    }

    func testStoringReportsEveryByte() throws {
        let runner = RecordingRunner(
            output: "/home/alice/.cache/devmachine-app/uploads/shot-20260930-143012.png\n")
        let service = FileUploadService(runner: runner, storagePolicy: .appManaged)
        let data = png()
        final class Seen: @unchecked Sendable { var last = 0 }
        let seen = Seen()

        _ = try service.store(
            data, name: shot, on: remote,
            onBytesWritten: { seen.last = $0 })

        XCTAssertEqual(seen.last, data.count)
        XCTAssertTrue(runner.args[0].last?.contains(".cache/devmachine-app/uploads") == true)
    }

    func testALocalStoreKeepsTheNameAndNeverOverwrites() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let service = FileUploadService(
            runner: RecordingRunner(output: ""), storagePolicy: .appManaged, localHome: home)
        let name = UploadName(stem: "my notes-20260930-143012", ext: ".txt")
        let local = TerminalKind.local(session: "Operator", path: "/tmp")

        let first = try service.store(Data("one".utf8), name: name, on: local)
        let second = try service.store(Data("two".utf8), name: name, on: local)

        let folder = home.appendingPathComponent(".cache/devmachine-app/uploads")
        XCTAssertEqual(first, folder.appendingPathComponent("my notes-20260930-143012.txt").path)
        XCTAssertEqual(second, folder.appendingPathComponent("my notes-20260930-143012-2.txt").path)
        XCTAssertEqual(try String(contentsOfFile: first, encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOfFile: second, encoding: .utf8), "two")
    }

    func testABitmapOnTheClipboardIsReadAsPNG() {
        let board = NSPasteboard(name: NSPasteboard.Name("dm.test.\(UUID().uuidString)"))
        board.clearContents()
        board.setData(png(), forType: .png)

        XCTAssertEqual(FileUploadService.pastedImage(from: board), .bitmap(png()))
    }

    func testAnImageFileOnTheClipboardKeepsItsFile() {
        let board = NSPasteboard(name: NSPasteboard.Name("dm.test.\(UUID().uuidString)"))
        board.clearContents()
        let url = URL(fileURLWithPath: "/Users/alice/Desktop/Screen Shot.png")
        board.writeObjects([url as NSURL])

        XCTAssertEqual(FileUploadService.pastedImage(from: board), .file(url))
    }

    func testTextOnTheClipboardIsNotAnImage() {
        let board = NSPasteboard(name: NSPasteboard.Name("dm.test.\(UUID().uuidString)"))
        board.clearContents()
        board.setString("hello", forType: .string)

        XCTAssertNil(FileUploadService.pastedImage(from: board))
    }

    @MainActor
    func testTheLabelNamesTheMachineTheFilesGoTo() {
        XCTAssertEqual(
            TerminalRegistry.sendingLabel(for: remote, names: ["a.png"]),
            "Sending a.png to acme-devmachine\u{2026}")
        XCTAssertEqual(
            TerminalRegistry.sendingLabel(for: remote, names: ["a.png", "b.txt"]),
            "Sending 2 files to acme-devmachine\u{2026}")
        XCTAssertEqual(
            TerminalRegistry.sendingLabel(for: .local(session: "Operator", path: "/tmp"), names: ["a.png"]),
            "Saving a.png\u{2026}")
    }

    @MainActor
    func testThePaneSaysWhereADropGoes() {
        XCTAssertEqual(
            TerminalRegistry.dropHint(for: remote), "Drop files to upload to acme-devmachine / dash")
        XCTAssertEqual(
            TerminalRegistry.dropHint(for: .local(session: "Operator", path: "/tmp")),
            "Drop files to upload to this Mac / Operator")
    }
}
