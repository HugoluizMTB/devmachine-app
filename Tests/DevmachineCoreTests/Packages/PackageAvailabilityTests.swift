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
                       .macOnly)
    }

    func testLinuxOnlyOnThisMac() {
        XCTAssertEqual(PackageAvailability.block(entry: entry("docker", platforms: ["linux"]), status: .available, target: mac),
                       .serverOnly)
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
