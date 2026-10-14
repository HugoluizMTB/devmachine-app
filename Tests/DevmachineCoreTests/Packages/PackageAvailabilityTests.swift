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

    func testAServerNeverReadBlocksNothing() {
        XCTAssertNil(PackageAvailability.block(entry: entry("brew", platforms: ["macos"]), status: .available, target: server))
        XCTAssertNil(PackageAvailability.block(entry: entry("docker", platforms: ["linux"]), status: .available, target: server))
    }

    func testMacOnlyOnALinuxServer() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("brew", platforms: ["macos"]), status: .available,
                                                 target: server, platform: "linux"), .otherSystem(runsOn: ["macos"]))
    }

    func testLinuxOnlyOnThisMac() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("docker", platforms: ["linux"]), status: .available, target: mac),
                       .otherSystem(runsOn: ["linux"]))
    }

    func testMacPackageFitsARemoteMac() {
        XCTAssertNil(PackageAvailability.block(entry: entry("brew", platforms: ["macos"]), status: .available,
                                               target: server, platform: "macos"))
    }

    func testLinuxOnlyOnARemoteMac() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("docker", platforms: ["linux"]), status: .available,
                                                 target: server, platform: "macos"), .otherSystem(runsOn: ["linux"]))
    }

    func testLinuxOnlyWorkspacePackageOnAMacMachine() {
        let dash = PackageTarget.workspace("dash", machine: "studio")
        let remoteControl = entry("claude-remote-control", scope: "workspace", platforms: ["linux"])
        XCTAssertEqual(PackageAvailability.block(entry: remoteControl, status: .available, target: dash,
                                                 platform: "macos"), .otherSystem(runsOn: ["linux"]))
        XCTAssertNil(PackageAvailability.block(entry: remoteControl, status: .available, target: dash,
                                               platform: "linux"))
        XCTAssertNil(PackageAvailability.block(entry: remoteControl, status: .available, target: dash, platform: nil))
    }

    func testTheBlockSaysWhichSystemsInAFewWords() {
        XCTAssertEqual(PackageBlock.otherSystem(runsOn: ["linux"]).label, "Linux only")
        XCTAssertEqual(PackageBlock.otherSystem(runsOn: ["macos"]).label, "macOS only")
        XCTAssertEqual(PackageBlock.otherSystem(runsOn: ["linux", "freebsd"]).label, "Runs on Linux, freebsd")
        XCTAssertEqual(PackageBlock.otherSystem(runsOn: ["linux"]).message, "Linux only.")
    }

    func testSystemFitTable() {
        let cases: [(platforms: [String], system: String?, installed: Bool, fit: PackageSystemFit)] = [
            ([], "linux", false, .fits),
            ([], "macos", true, .fits),
            ([], nil, false, .fits),
            (["linux"], nil, false, .fits),
            (["macos"], nil, true, .fits),
            (["linux"], "linux", false, .fits),
            (["linux", "macos"], "macos", false, .fits),
            (["linux"], "macos", false, .blocked("Linux only")),
            (["macos"], "linux", false, .blocked("macOS only")),
            (["linux", "freebsd"], "macos", false, .blocked("Runs on Linux, freebsd")),
            (["linux"], "macos", true, .removableOnly("Linux only")),
            (["macos"], "linux", true, .removableOnly("macOS only")),
        ]
        for item in cases {
            XCTAssertEqual(
                PackageAvailability.systemFit(platforms: item.platforms, system: item.system, installed: item.installed),
                item.fit, "\(item.platforms) on \(item.system ?? "unknown"), installed \(item.installed)")
        }
    }

    func testSystemFitTicksOnlyWhatCanGoThereOrComeOff() {
        XCTAssertTrue(PackageSystemFit.fits.canTick)
        XCTAssertNil(PackageSystemFit.fits.label)
        XCTAssertFalse(PackageSystemFit.blocked("Linux only").canTick)
        XCTAssertEqual(PackageSystemFit.blocked("Linux only").label, "Linux only")
        XCTAssertTrue(PackageSystemFit.removableOnly("Linux only").canTick)
        XCTAssertEqual(PackageSystemFit.removableOnly("Linux only").label, "Linux only")
    }

    func testSystemFitOverSeveralPlacesFitsWhenOneFits() {
        let linuxOnly = ["linux"]
        XCTAssertEqual(PackageAvailability.systemFit(platforms: linuxOnly, on: []), .fits)
        XCTAssertEqual(PackageAvailability.systemFit(
            platforms: linuxOnly, on: [(system: "macos", installed: false), (system: "linux", installed: false)]), .fits)
        XCTAssertEqual(PackageAvailability.systemFit(
            platforms: linuxOnly, on: [(system: "macos", installed: false), (system: nil, installed: false)]), .fits)
        XCTAssertEqual(PackageAvailability.systemFit(
            platforms: linuxOnly, on: [(system: "macos", installed: false), (system: "macos", installed: true)]),
            .removableOnly("Linux only"))
        XCTAssertEqual(PackageAvailability.systemFit(
            platforms: linuxOnly, on: [(system: "macos", installed: false)]), .blocked("Linux only"))
    }

    func testThisMacIsMacOSEvenWhenTheCLISaysNothing() {
        XCTAssertEqual(PackageAvailability.system(of: mac, reported: nil), "macos")
        XCTAssertEqual(PackageAvailability.system(of: server, reported: "linux"), "linux")
        XCTAssertNil(PackageAvailability.system(of: server, reported: nil))
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
