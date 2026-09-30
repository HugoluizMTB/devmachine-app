import XCTest
@testable import DevmachineCore

private final class FailingMover: FileMoving, @unchecked Sendable {
    let real = FileManager.default
    var failMoveNumber: Int?
    private var moves = 0

    func copyItem(at source: URL, to destination: URL) throws {
        try real.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        moves += 1
        if moves == failMoveNumber { throw CocoaError(.fileWriteNoPermission) }
        try real.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try real.removeItem(at: url)
    }
}

final class BundleSwapperTests: XCTestCase {
    private var folder: URL!
    private var current: URL!
    private var incoming: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString)")
        current = folder.appendingPathComponent("Applications/Devmachine.app")
        incoming = folder.appendingPathComponent("mount/Devmachine.app")
        try makeBundle(at: current, marker: "old")
        try makeBundle(at: incoming, marker: "new")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeBundle(at url: URL, marker: String) throws {
        let macOS = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: macOS.appendingPathComponent("DevmachineApp"))
    }

    private func marker(at url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url.appendingPathComponent("Contents/MacOS/DevmachineApp")), as: UTF8.self)
    }

    private func siblings() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: current.deletingLastPathComponent().path).sorted()
    }

    func testStagingCopiesBesideTheCurrentBundle() throws {
        let swapper = BundleSwapper()
        let staged = try swapper.stage(incoming, beside: current)
        XCTAssertEqual(staged.deletingLastPathComponent().path, current.deletingLastPathComponent().path)
        XCTAssertEqual(try marker(at: staged), "new")
        XCTAssertEqual(try marker(at: current), "old")
    }

    func testSwapPutsTheNewBundleInPlaceAndRemovesTheOld() throws {
        let swapper = BundleSwapper()
        let staged = try swapper.stage(incoming, beside: current)
        try swapper.swap(staged, into: current)

        XCTAssertEqual(try marker(at: current), "new")
        XCTAssertEqual(try siblings(), ["Devmachine.app"])
    }

    func testWhenTheNewBundleCannotMoveInTheOldOneIsPutBack() throws {
        let mover = FailingMover()
        let swapper = BundleSwapper(files: mover)
        let staged = try swapper.stage(incoming, beside: current)
        mover.failMoveNumber = 2

        XCTAssertThrowsError(try swapper.swap(staged, into: current)) { error in
            guard case .swapFailed(let rolledBack, _) = error as? UpdateInstallError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(rolledBack)
        }
        XCTAssertEqual(try marker(at: current), "old")
        XCTAssertEqual(try siblings(), ["Devmachine.app"])
    }

    func testWhenTheOldBundleCannotMoveAsideNothingChanges() throws {
        let mover = FailingMover()
        let swapper = BundleSwapper(files: mover)
        let staged = try swapper.stage(incoming, beside: current)
        mover.failMoveNumber = 1

        XCTAssertThrowsError(try swapper.swap(staged, into: current))
        XCTAssertEqual(try marker(at: current), "old")
        XCTAssertEqual(try siblings(), ["Devmachine.app"])
    }

    func testAFolderItCannotWriteIsReported() throws {
        let swapper = BundleSwapper(isWritable: { _ in false })
        XCTAssertFalse(swapper.canReplace(current))
        XCTAssertTrue(BundleSwapper(isWritable: { _ in true }).canReplace(current))
    }
}
