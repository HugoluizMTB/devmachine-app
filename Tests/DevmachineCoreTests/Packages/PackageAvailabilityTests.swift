import XCTest
@testable import DevmachineCore

final class PackageAvailabilityTests: XCTestCase {
    private func entry(_ name: String, scope: String = "machine", platforms: [String] = []) -> PackageEntry {
        PackageEntry(name: name, scope: scope, source: "release", summary: "", category: nil,
                     platforms: platforms, needs: [], credentialNames: [], installedOn: [])
    }

    private let server = PackageTarget.machine("main", isSelf: false)
    private let mac = PackageTarget.machine("mac", isSelf: true)

    func testFreeToToggle() {
        XCTAssertNil(PackageAvailability.block(entry: entry("docker"), status: .available, target: server))
    }

    func testWrongScope() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("node", scope: "workspace"), status: .available, target: server),
                       .wrongScope("workspace"))
    }

    func testNoRecipe() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("ghost", scope: ""), status: .applied, target: server), .noRecipe)
    }

    func testMacOnlyOnServer() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("brew", platforms: ["macos"]), status: .available, target: server),
                       .otherSystem(runsOn: ["macos"]))
    }

    func testLinuxOnlyOnThisMac() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("docker", platforms: ["linux"]), status: .available, target: mac),
                       .otherSystem(runsOn: ["linux"]))
    }

    func testTheReasonIsShort() {
        XCTAssertEqual(PackageBlock.otherSystem(runsOn: ["linux"]).message, "Linux only.")
        XCTAssertEqual(PackageBlock.otherSystem(runsOn: ["macos"]).label, "macOS only")
    }

    func testARemoteMacTakesMacPackagesAndRefusesLinuxOnes() {
        let platforms = MachinePlatforms(known: ["studio": .macos])
        let studio = PackageTarget.machine("studio", isSelf: false)
        XCTAssertNil(PackageAvailability.block(
            entry: entry("mac-ports", platforms: ["macos"]), status: .available, target: studio, platforms: platforms))
        XCTAssertEqual(PackageAvailability.block(
            entry: entry("docker", platforms: ["linux"]), status: .available, target: studio, platforms: platforms),
            .otherSystem(runsOn: ["linux"]))
        XCTAssertNil(PackageAvailability.block(
            entry: entry("git", platforms: []), status: .available, target: studio, platforms: platforms))
        XCTAssertNil(PackageAvailability.block(
            entry: entry("tmux", platforms: ["linux", "macos"]), status: .available, target: studio, platforms: platforms))
    }

    func testAWorkspaceFollowsItsMachine() {
        let platforms = MachinePlatforms(known: ["studio": .macos])
        XCTAssertEqual(PackageAvailability.block(
            entry: entry("linux-tools", scope: "workspace", platforms: ["linux"]), status: .available,
            target: .workspace("acme", machine: "studio"), platforms: platforms),
            .otherSystem(runsOn: ["linux"]))
    }

    func testAMachineNeverReadBlocksNothing() {
        let unknown = MachinePlatforms(known: [:])
        XCTAssertNil(PackageAvailability.block(
            entry: entry("brew", platforms: ["macos"]), status: .available, target: server, platforms: unknown))
        XCTAssertNil(PackageAvailability.block(
            entry: entry("docker", platforms: ["linux"]), status: .available, target: server, platforms: unknown))
        XCTAssertTrue(PackageBatch.fits(entry("brew", platforms: ["macos"]), on: server, platforms: unknown))
        XCTAssertFalse(PackageBatch.fits(
            entry("docker", platforms: ["linux"]), on: .machine("studio", isSelf: false),
            platforms: MachinePlatforms(known: ["studio": .macos])))
    }

    func testEssentialsCannotBeRemoved() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("essentials"), status: .applied, target: server), .essentials)
        XCTAssertNil(PackageAvailability.block(entry: entry("essentials"), status: .available, target: server))
    }

    func testAccountPackage() {
        let acme = PackageTarget.workspace("acme", machine: "main")
        XCTAssertEqual(PackageAvailability.block(entry: entry("workspace", scope: "workspace"),
                                                 status: .appliedAsDependency(of: "workspace"), target: acme), .account)
    }

    func testDependencyIsBlocked() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("caddy"), status: .appliedAsDependency(of: "essentials"),
                                                 target: server), .dependency(of: "essentials"))
    }
}
