import XCTest
@testable import DevmachineCore

final class GitHubReleaseTests: XCTestCase {
    static let json = """
    {
      "tag_name": "v0.1.3",
      "name": "Devmachine 0.1.3",
      "body": "sha256: \(String(repeating: "ab", count: 32))",
      "draft": false,
      "prerelease": false,
      "html_url": "https://github.com/example/app-releases/releases/tag/v0.1.3",
      "published_at": "2026-09-30T12:00:00Z",
      "assets": [
        {"name": "Devmachine-0.1.3.dmg", "browser_download_url": "https://example.com/Devmachine-0.1.3.dmg", "size": 1200},
        {"name": "Devmachine-0.1.3.dmg.sha256", "browser_download_url": "https://example.com/Devmachine-0.1.3.dmg.sha256", "size": 90},
        {"name": "Devmachine.dmg", "browser_download_url": "https://example.com/Devmachine.dmg", "size": 1200}
      ]
    }
    """

    func testDecodesTheFieldsTheUpdaterUses() throws {
        let release = try GitHubRelease.decode(Data(Self.json.utf8))
        XCTAssertEqual(release.tagName, "v0.1.3")
        XCTAssertEqual(release.version, SemanticVersion("0.1.3"))
        XCTAssertFalse(release.isDraft)
        XCTAssertFalse(release.isPrerelease)
        XCTAssertEqual(release.htmlURL?.absoluteString, "https://github.com/example/app-releases/releases/tag/v0.1.3")
        XCTAssertEqual(release.assets.count, 3)
    }

    func testFindsTheVersionedDiskImageAndItsDigest() throws {
        let release = try GitHubRelease.decode(Data(Self.json.utf8))
        XCTAssertEqual(release.appDiskImage?.name, "Devmachine-0.1.3.dmg")
        XCTAssertEqual(release.appDiskImageDigest?.name, "Devmachine-0.1.3.dmg.sha256")
    }

    func testReadsTheDigestTheReleaseBodyCarries() throws {
        let release = try GitHubRelease.decode(Data(Self.json.utf8))
        XCTAssertEqual(release.bodyDigest, String(repeating: "ab", count: 32))
    }

    func testNotesLeaveTheDigestLineOut() {
        let release = GitHubRelease(
            tagName: "v0.1.3", body: "Faster start.\n\nsha256: \(String(repeating: "0", count: 64))\n")
        XCTAssertEqual(release.notes, "Faster start.")
    }

    func testAMissingBodyOrAssetListIsNotAnError() throws {
        let release = try GitHubRelease.decode(Data(#"{"tag_name":"v1.0.0"}"#.utf8))
        XCTAssertEqual(release.body, "")
        XCTAssertEqual(release.assets, [])
        XCTAssertNil(release.appDiskImage)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try GitHubRelease.decode(Data("<html>".utf8)))
    }
}
