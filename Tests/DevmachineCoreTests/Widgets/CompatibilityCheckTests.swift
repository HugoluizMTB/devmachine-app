import XCTest
@testable import DevmachineCore

final class CompatibilityCheckTests: XCTestCase {
    private let manifest = WidgetAppManifest(
        engine: "1.0", requiresCLI: SemanticVersion(major: 0, minor: 9, patch: 0), requiresPackagesTag: "v39")

    private func outdated(_ pinned: String, latest: String = "v39", newer: Bool = false) -> PackagesOutdated {
        PackagesOutdated(pinned: pinned, latest: latest, newer: newer, notesURL: nil)
    }

    private func evaluate(_ cli: String?, _ packages: PackagesOutdated?) -> CompatibilityStatus {
        CompatibilityCheck.evaluate(manifest: manifest, cliVersionOutput: cli, packages: packages)
    }

    func testBothAtTheMinimumIsOK() {
        XCTAssertEqual(evaluate("devmachine 0.9.0", outdated("v39")), .ok)
    }

    func testOnlyTheCLIBehindAsksForTheCLIOnly() {
        XCTAssertEqual(evaluate("devmachine 0.8.1", outdated("v39")), .behind(CompatibilityGap(
            cliBehind: true, packagesBehind: false, installedCLI: SemanticVersion(major: 0, minor: 8, patch: 1),
            pinnedPackages: "v39", command: .cliOnly)))
    }

    func testOnlyThePinBehindAsksForNoMachines() {
        XCTAssertEqual(evaluate("devmachine 0.9.0", outdated("v38")), .behind(CompatibilityGap(
            cliBehind: false, packagesBehind: true, installedCLI: SemanticVersion(major: 0, minor: 9, patch: 0),
            pinnedPackages: "v38", command: .noMachines)))
    }

    func testBothBehindAsksForNoMachines() {
        guard case let .behind(gap) = evaluate("devmachine 0.8.1", outdated("v38")) else { return XCTFail("not behind") }
        XCTAssertTrue(gap.cliBehind)
        XCTAssertTrue(gap.packagesBehind)
        XCTAssertEqual(gap.command, .noMachines)
    }

    func testACLITooOldForNoMachinesUpdatesItselfFirst() {
        guard case let .behind(gap) = evaluate("devmachine 0.7.30", outdated("v30")) else { return XCTFail("not behind") }
        XCTAssertEqual(gap.command, .cliOnly)
    }

    func testADevBuildWithNoPinReadIsUnknown() {
        XCTAssertEqual(evaluate("dev", nil), .unknown)
        XCTAssertEqual(evaluate(nil, outdated("")), .unknown)
    }

    func testADevBuildWithAnOldPinIsBehindOnPackagesOnly() {
        guard case let .behind(gap) = evaluate("dev", outdated("v30")) else { return XCTFail("not behind") }
        XCTAssertFalse(gap.cliBehind)
        XCTAssertNil(gap.installedCLI)
        XCTAssertEqual(gap.command, .noMachines)
    }

    func testANewerReleaseAloneIsOnlyNewerAvailable() {
        XCTAssertEqual(evaluate("devmachine 0.9.0", outdated("v39", latest: "v41", newer: true)), .newerAvailable)
    }

    func testCopyNamesWhatIsBehind() {
        let gap = CompatibilityGap(
            cliBehind: true, packagesBehind: true, installedCLI: SemanticVersion(major: 0, minor: 8, patch: 1),
            pinnedPackages: "v38", command: .noMachines)
        XCTAssertEqual(CompatibilityCopy.title(gap), "Home widgets need a newer CLI and packages")
        XCTAssertEqual(
            CompatibilityCopy.note(gap, manifest: manifest),
            "This app needs CLI 0.9.0 and packages v39 or newer. You have CLI 0.8.1 and packages v38.")
        XCTAssertEqual(CLIUpdateCommand.cliOnly.commandLine, "devmachine update --cli-only")
        XCTAssertEqual(CLIUpdateCommand.noMachines.commandLine, "devmachine update --no-machines")
    }

    func testTheCurrentManifestImplementsTheGoldenEngine() {
        XCTAssertEqual(WidgetAppManifest.current.engine, WidgetContract.current.engine)
        XCTAssertNotNil(WidgetAppManifest.current.requiresPackages)
    }

    func testTheCurrentManifestNeedsTheReleasesThatShipEngine16() {
        XCTAssertEqual(WidgetAppManifest.current.requiresCLI, SemanticVersion(major: 0, minor: 10, patch: 0))
        XCTAssertEqual(WidgetAppManifest.current.requiresPackagesTag, "v41")
    }
}
