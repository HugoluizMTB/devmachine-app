import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Downloads the published release and installs it into a temporary folder,
/// with every real check. Off by default: it needs the network. Run with
/// `DEVMACHINE_UPDATE_E2E=1 swift test --filter UpdateInstallerEndToEndTests`.
final class UpdateInstallerEndToEndTests: XCTestCase {
    func testInstallsThePublishedReleaseIntoATemporaryFolder() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVMACHINE_UPDATE_E2E"] == "1")
        let feed = ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: URLSessionHTTPFetcher(), userAgent: "Devmachine")
        let release = try await feed.latest(cached: nil).release
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID().uuidString)")
        let current = folder.appendingPathComponent("Applications/Devmachine.app")
        try FileManager.default.createDirectory(
            at: current.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let installer = DiskImageUpdateInstaller(
            currentApp: current, bundleID: "app.devmachine.mac",
            runningTeamID: try await publishedTeam(release, folder: folder))
        let outcome = try await installer.install(release: release) { _ in }

        XCTAssertEqual(outcome, .replaced(current))
        XCTAssertEqual(try BundleInfo.read(appAt: current).version.flatMap(SemanticVersion.init), release.version)
        XCTAssertNoThrow(try SystemCodeSignatureChecker().verifySignature(of: current))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: current.deletingLastPathComponent().path),
            ["Devmachine.app"])
    }

    func testRefusesTheReleaseForAnotherTeam() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVMACHINE_UPDATE_E2E"] == "1")
        let feed = ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: URLSessionHTTPFetcher(), userAgent: "Devmachine")
        let release = try await feed.latest(cached: nil).release
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID().uuidString)")
        let current = folder.appendingPathComponent("Applications/Devmachine.app")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let installer = DiskImageUpdateInstaller(
            currentApp: current, bundleID: "app.devmachine.mac", runningTeamID: "ZZZZZZZZZZ")
        do {
            _ = try await installer.install(release: release) { _ in }
            XCTFail("installed a release signed by another team")
        } catch {
            guard case .teamMismatch = error as? UpdateInstallError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: current.path), [])
    }

    /// The team that signed the release, read from its own disk image, stands
    /// in for the running app's: this test process is not signed by it.
    private func publishedTeam(_ release: GitHubRelease, folder: URL) async throws -> String? {
        let image = try XCTUnwrap(release.appDiskImage)
        let dmg = try await URLSessionDownloader().download(
            image.downloadURL, to: folder.appendingPathComponent("probe.dmg"), progress: { _ in })
        let root = folder.appendingPathComponent("probe-mount")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let attach = try ProcessRunner().runCapturing(
            executable: "/usr/bin/hdiutil", args: DiskImage.attachArguments(image: dmg, mountRoot: root),
            environment: nil)
        let mount = try XCTUnwrap(DiskImage.mountPoint(fromAttachOutput: Data(attach.stdout.utf8)))
        defer { _ = try? ProcessRunner().runCapturing(
            executable: "/usr/bin/hdiutil", args: DiskImage.detachArguments(mountPoint: mount), environment: nil) }
        return try SystemCodeSignatureChecker().teamIdentifier(of: mount.appendingPathComponent("Devmachine.app"))
    }
}
