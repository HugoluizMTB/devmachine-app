import XCTest
@testable import DevmachineCore

private final class FakeSignatures: CodeSignatureChecking, @unchecked Sendable {
    var signatureError: Error?
    var gatekeeperError: Error?
    var team: String? = "TEAM123456"
    private(set) var calls: [String] = []

    func verifySignature(of app: URL) throws {
        calls.append("codesign")
        if let signatureError { throw signatureError }
    }

    func teamIdentifier(of app: URL) throws -> String? {
        calls.append("team")
        return team
    }

    func assessGatekeeper(of app: URL) throws {
        calls.append("spctl")
        if let gatekeeperError { throw gatekeeperError }
    }
}

private struct Boom: Error, Equatable {}

final class UpdateBundleVerifierTests: XCTestCase {
    private let app = URL(fileURLWithPath: "/Volumes/Devmachine/Devmachine.app")
    private let good = BundleInfo(bundleID: "app.devmachine.mac", version: "0.1.3")

    private func verify(
        _ info: BundleInfo, signatures: FakeSignatures, runningTeam: String? = "TEAM123456"
    ) throws {
        try UpdateBundleVerifier(
            expectedBundleID: "app.devmachine.mac", runningTeamID: runningTeam, signatures: signatures
        ).verify(app: app, info: info, expectedVersion: SemanticVersion("0.1.3")!)
    }

    func testAGoodBundlePassesEveryCheck() throws {
        let signatures = FakeSignatures()
        try verify(good, signatures: signatures)
        XCTAssertEqual(signatures.calls, ["codesign", "team", "spctl"])
    }

    func testAnotherBundleIDIsRefused() {
        XCTAssertThrowsError(try verify(
            BundleInfo(bundleID: "com.example.other", version: "0.1.3"), signatures: FakeSignatures())
        ) { XCTAssertEqual($0 as? UpdateInstallError, .wrongBundleID("com.example.other")) }
    }

    func testAnotherVersionIsRefused() {
        XCTAssertThrowsError(try verify(
            BundleInfo(bundleID: "app.devmachine.mac", version: "0.1.2"), signatures: FakeSignatures())
        ) { XCTAssertEqual($0 as? UpdateInstallError, .wrongVersion(expected: "0.1.3", found: "0.1.2")) }
    }

    func testABrokenSignatureIsRefused() {
        let signatures = FakeSignatures()
        signatures.signatureError = UpdateInstallError.signatureInvalid("a sealed resource is missing")
        XCTAssertThrowsError(try verify(good, signatures: signatures)) {
            XCTAssertEqual($0 as? UpdateInstallError, .signatureInvalid("a sealed resource is missing"))
        }
        XCTAssertEqual(signatures.calls, ["codesign"])
    }

    func testAnotherTeamIsRefused() {
        let signatures = FakeSignatures()
        signatures.team = "OTHER99999"
        XCTAssertThrowsError(try verify(good, signatures: signatures)) {
            XCTAssertEqual($0 as? UpdateInstallError, .teamMismatch(expected: "TEAM123456", found: "OTHER99999"))
        }
    }

    func testAnUnsignedUpdateIsRefused() {
        let signatures = FakeSignatures()
        signatures.team = nil
        XCTAssertThrowsError(try verify(good, signatures: signatures)) {
            XCTAssertEqual($0 as? UpdateInstallError, .teamMismatch(expected: "TEAM123456", found: nil))
        }
    }

    func testARunningCopyWithoutATeamCannotVouchForAnUpdate() {
        let signatures = FakeSignatures()
        XCTAssertThrowsError(try verify(good, signatures: signatures, runningTeam: nil)) {
            XCTAssertEqual($0 as? UpdateInstallError, .runningAppNotSigned)
        }
        XCTAssertTrue(signatures.calls.isEmpty)
    }

    func testGatekeeperRefusingIsRefused() {
        let signatures = FakeSignatures()
        signatures.gatekeeperError = UpdateInstallError.gatekeeperRejected("rejected")
        XCTAssertThrowsError(try verify(good, signatures: signatures)) {
            XCTAssertEqual($0 as? UpdateInstallError, .gatekeeperRejected("rejected"))
        }
    }

    func testReadsTheBundleInfoFromDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
        let contents = folder.appendingPathComponent("Devmachine.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plist: [String: Any] = ["CFBundleIdentifier": "app.devmachine.mac", "CFBundleShortVersionString": "0.1.3"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertEqual(try BundleInfo.read(appAt: folder.appendingPathComponent("Devmachine.app")), good)
    }

    func testABundleWithoutInfoPlistThrows() {
        XCTAssertThrowsError(try BundleInfo.read(appAt: URL(fileURLWithPath: "/nonexistent/Devmachine.app")))
    }
}
