import Foundation

public struct BundleInfo: Equatable, Sendable {
    public let bundleID: String?
    public let version: String?

    public init(bundleID: String?, version: String?) {
        self.bundleID = bundleID
        self.version = version
    }

    public static func read(appAt app: URL) throws -> BundleInfo {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return BundleInfo(
            bundleID: plist?["CFBundleIdentifier"] as? String,
            version: plist?["CFBundleShortVersionString"] as? String)
    }
}

public protocol CodeSignatureChecking: Sendable {
    func verifySignature(of app: URL) throws
    func teamIdentifier(of app: URL) throws -> String?
    func assessGatekeeper(of app: URL) throws
}

/// What a downloaded app must be before it replaces this one: the same
/// bundle, the version the release promised, intact, signed by the team that
/// signed the running copy, and accepted by Gatekeeper.
public struct UpdateBundleVerifier: Sendable {
    let expectedBundleID: String
    let runningTeamID: String?
    let signatures: any CodeSignatureChecking

    public init(expectedBundleID: String, runningTeamID: String?, signatures: any CodeSignatureChecking) {
        self.expectedBundleID = expectedBundleID
        self.runningTeamID = runningTeamID
        self.signatures = signatures
    }

    public func verify(app: URL, info: BundleInfo, expectedVersion: SemanticVersion) throws {
        guard let runningTeamID else { throw UpdateInstallError.runningAppNotSigned }
        guard info.bundleID == expectedBundleID else { throw UpdateInstallError.wrongBundleID(info.bundleID) }
        guard info.version.flatMap(SemanticVersion.init) == expectedVersion else {
            throw UpdateInstallError.wrongVersion(expected: expectedVersion.description, found: info.version)
        }
        try signatures.verifySignature(of: app)
        let team = try signatures.teamIdentifier(of: app)
        guard team == runningTeamID else {
            throw UpdateInstallError.teamMismatch(expected: runningTeamID, found: team)
        }
        try signatures.assessGatekeeper(of: app)
    }
}
