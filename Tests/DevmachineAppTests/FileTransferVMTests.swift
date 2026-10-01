import XCTest
import DevmachineCore
@testable import DevmachineApp

/// The Files tab's transfers through a real CLI against a throwaway VM. Skips
/// unless DEVMACHINE_TRANSFER_CLI names a CLI build and
/// DEVMACHINE_TRANSFER_CONFIG a configuration whose workspace `acme` holds
/// `~/proj/my report ção.txt` and `~/proj/site/`.
@MainActor
final class FileTransferVMTests: XCTestCase {
    private var transfers: FileTransferStore!
    private var downloads: URL!

    override func setUp() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let cli = environment["DEVMACHINE_TRANSFER_CLI"],
              let config = environment["DEVMACHINE_TRANSFER_CONFIG"]
        else { throw XCTSkip("no VM configured for transfers") }
        downloads = FileManager.default.temporaryDirectory.appendingPathComponent("dm-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let processEnvironment = environment.merging(["DEVMACHINE_CONFIG": config]) { _, new in new }
        transfers = FileTransferStore(
            cli: { DevmachineCLI(executable: cli, processEnvironment: processEnvironment) },
            downloadsDirectory: downloads,
            dragDirectory: downloads.appendingPathComponent("drag"),
            home: NSHomeDirectory())
    }

    override func tearDown() async throws {
        if let downloads { try? FileManager.default.removeItem(at: downloads) }
    }

    func testDownloadUploadAndDragAgainstTheVM() async throws {
        let report = "/home/acme/proj/my report ção.txt"

        await transfers.download([report], workspace: "acme")
        let saved = downloads.appendingPathComponent("my report ção.txt")
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "plain body\n")
        XCTAssertEqual(transfers.notice?.reveal, saved)
        print("notice:", transfers.notice?.title ?? "none", "|", transfers.notice?.detail ?? "")

        await transfers.download([report], workspace: "acme")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("my report ção-2.txt").path))
        print("notice:", transfers.notice?.title ?? "none", "|", transfers.notice?.detail ?? "")

        await transfers.download(["/home/acme/proj/site"], workspace: "acme")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("site.tar.gz").path))
        print("notice:", transfers.notice?.title ?? "none", "|", transfers.notice?.detail ?? "")

        let dragged = try await transfers.exportForDrag(report, workspace: "acme")
        XCTAssertEqual(dragged.lastPathComponent, "my report ção.txt")
        XCTAssertEqual(try String(contentsOf: dragged, encoding: .utf8), "plain body\n")
        print("drag export:", dragged.path)

        let local = downloads.appendingPathComponent("it's \"quoted\" ção.png")
        try Data("png bytes".utf8).write(to: local)
        let landed = await transfers.upload([local], into: "/home/acme/proj/assets", workspace: "acme")
        let remote = try XCTUnwrap(landed.first)
        XCTAssertTrue(remote.hasPrefix("/home/acme/proj/assets/it's \"quoted\" ção-"), remote)
        print("notice:", transfers.notice?.title ?? "none", "|", transfers.notice?.detail ?? "")

        let back = try await transfers.exportForDrag(remote, workspace: "acme")
        XCTAssertEqual(try String(contentsOf: back, encoding: .utf8), "png bytes")

        await transfers.download(["/home/acme/proj/missing.txt"], workspace: "acme")
        XCTAssertEqual(transfers.notice?.failed, true)
        print("notice:", transfers.notice?.title ?? "none", "|", transfers.notice?.detail ?? "")
    }
}
