import XCTest
@testable import DevmachineCore

final class PackageBatchTests: XCTestCase {
    private let main = PackageTarget.machine("main", isSelf: false)
    private let backup = PackageTarget.machine("backup", isSelf: false)
    private let acme = PackageTarget.workspace("acme", machine: "main")

    private func entry(_ name: String, scope: String = "machine") -> PackageEntry {
        PackageEntry(name: name, scope: scope, source: "release", summary: "", category: nil,
                     platforms: [], needs: [], credentialNames: [], installedOn: [])
    }

    func testInstallingOnTwoMachinesAndAWorkspaceSkipsWhatDoesNotFitOrIsThere() {
        let batch = PackageBatch.plan(
            packages: ["docker", "nodejs"], targets: [main, backup, acme], action: .install,
            entries: [entry("docker"), entry("nodejs", scope: "workspace")],
            statuses: { $0 == backup ? ["docker": .applied] : [:] })

        XCTAssertEqual(batch.edits.map(\.target), [main, acme])
        XCTAssertEqual(batch.edits.map(\.changes), [
            PackageChanges(adds: ["docker"], removes: []), PackageChanges(adds: ["nodejs"], removes: []),
        ])
        XCTAssertEqual(batch.skips, [
            PackageSkip(package: "nodejs", target: main, reason: "Goes on a workspace."),
            PackageSkip(package: "docker", target: backup, reason: "Already there."),
            PackageSkip(package: "nodejs", target: backup, reason: "Goes on a workspace."),
            PackageSkip(package: "docker", target: acme, reason: "Goes on a machine."),
        ])
    }

    func testALinuxOnlyPackageSkipsAMachineTheCLIReadAsAMac() {
        let docker = PackageEntry(name: "docker", scope: "machine", source: "release", summary: "", category: nil,
                                  platforms: ["linux"], needs: [], credentialNames: [], installedOn: [])
        let batch = PackageBatch.plan(
            packages: ["docker"], targets: [main, backup], action: .install,
            entries: [docker], statuses: { _ in [:] }, platform: { $0 == backup ? "macos" : "linux" })

        XCTAssertEqual(batch.edits.map(\.target), [main])
        XCTAssertEqual(batch.skips, [
            PackageSkip(package: "docker", target: backup, reason: "Linux only."),
        ])
    }

    func testRemovingOnlyTouchesTargetsThatHaveIt() {
        let batch = PackageBatch.plan(
            packages: ["redis"], targets: [main, backup], action: .remove,
            entries: [entry("redis")],
            statuses: { $0 == main ? ["redis": .applied] : [:] })

        XCTAssertEqual(batch.edits.map(\.target), [main])
        XCTAssertEqual(batch.edits.first?.changes, PackageChanges(adds: [], removes: ["redis"]))
        XCTAssertEqual(batch.skips, [PackageSkip(package: "redis", target: backup, reason: "Not there.")])
    }

    func testEssentialsIsNeverRemoved() {
        let batch = PackageBatch.plan(
            packages: ["essentials"], targets: [main], action: .remove,
            entries: [entry("essentials")], statuses: { _ in ["essentials": .applied] })

        XCTAssertTrue(batch.isEmpty)
        XCTAssertEqual(batch.skips.map(\.reason), ["Every machine keeps essentials."])
    }

    func testAPackageFitsOnlyTargetsOfItsScope() {
        XCTAssertTrue(PackageBatch.fits(entry("docker"), on: main))
        XCTAssertFalse(PackageBatch.fits(entry("docker"), on: acme))
        XCTAssertTrue(PackageBatch.fits(entry("nodejs", scope: "workspace"), on: acme))
    }

    func testAnInstalledPackageForAnotherSystemCanStillBeRemoved() {
        let docker = PackageEntry(name: "docker", scope: "machine", source: "release", summary: "", category: nil,
                                  platforms: ["linux"], needs: [], credentialNames: [], installedOn: [])
        let batch = PackageBatch.plan(
            packages: ["docker"], targets: [backup], action: .remove,
            entries: [docker], statuses: { _ in ["docker": .applied] }, platform: { _ in "macos" })

        XCTAssertEqual(batch.edits.map(\.target), [backup])
        XCTAssertEqual(batch.skips, [])
    }

    func testAPackageForAnotherSystemOnlyFitsWhereItIsInstalled() {
        let docker = PackageEntry(name: "docker", scope: "machine", source: "release", summary: "", category: nil,
                                  platforms: ["linux"], needs: [], credentialNames: [], installedOn: [])
        XCTAssertFalse(PackageBatch.fits(docker, on: backup, platform: "macos"))
        XCTAssertTrue(PackageBatch.fits(docker, on: backup, platform: "macos", status: .applied))
        XCTAssertTrue(PackageBatch.fits(docker, on: backup, platform: nil))
    }
}
