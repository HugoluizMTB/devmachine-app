import XCTest
@testable import DevmachineCore

final class ReleaseDigestTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let helloDigest = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

    func testParsesTheShasumFormat() {
        XCTAssertEqual(ReleaseDigest.parse("\(helloDigest)  Devmachine-0.1.3.dmg\n"), helloDigest)
    }

    func testParsesABareDigestInAnyCase() {
        XCTAssertEqual(ReleaseDigest.parse(helloDigest.uppercased()), helloDigest)
    }

    func testRefusesTextWithoutADigest() {
        XCTAssertNil(ReleaseDigest.parse("Not Found"))
        XCTAssertNil(ReleaseDigest.parse(String(repeating: "a", count: 63)))
    }

    func testHashesAFile() throws {
        let file = folder.appendingPathComponent("hello")
        try Data("hello".utf8).write(to: file)
        XCTAssertEqual(try ReleaseDigest.sha256(ofFileAt: file), helloDigest)
    }

    func testHashesAFileLargerThanOneChunk() throws {
        let file = folder.appendingPathComponent("large")
        try Data(repeating: 0x61, count: 3 * 1024 * 1024 + 7).write(to: file)
        XCTAssertEqual(try ReleaseDigest.sha256(ofFileAt: file).count, 64)
    }

    func testVerifyPassesOnAMatchAndThrowsOnAMismatch() throws {
        let file = folder.appendingPathComponent("hello")
        try Data("hello".utf8).write(to: file)
        XCTAssertNoThrow(try ReleaseDigest.verify(fileAt: file, expected: helloDigest.uppercased()))
        let wrong = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try ReleaseDigest.verify(fileAt: file, expected: wrong)) { error in
            XCTAssertEqual(error as? UpdateInstallError, .digestMismatch(expected: wrong, actual: helloDigest))
        }
    }
}
