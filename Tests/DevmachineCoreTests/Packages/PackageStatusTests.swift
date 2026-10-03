import XCTest
@testable import DevmachineCore

final class PackageStatusTests: XCTestCase {
    private func entry(_ name: String, scope: String = "machine", needs: [String] = [], on: [String] = []) -> PackageEntry {
        PackageEntry(name: name, scope: scope, source: "release", summary: "", category: nil,
                     platforms: [], needs: needs, credentialNames: [], installedOn: on)
    }

    private let main = PackageTarget.machine("main", isSelf: false)

    func testDeclaredAndLockedIsApplied() {
        let lock = PackagesLock(machines: ["main": [.init(name: "docker")]])
        let s = PackageStatusCheck.evaluate(entries: [entry("docker", on: ["machine main"])], target: main, lock: lock)
        XCTAssertEqual(s["docker"], .applied)
    }

    func testDeclaredNotLockedIsPendingInstall() {
        let s = PackageStatusCheck.evaluate(
            entries: [entry("docker", on: ["machine main"])], target: main, lock: PackagesLock(machines: [:]))
        XCTAssertEqual(s["docker"], .pendingInstall)
    }

    func testLockedNotIncludedIsPendingRemove() {
        let lock = PackagesLock(machines: ["main": [.init(name: "node")]])
        let s = PackageStatusCheck.evaluate(entries: [entry("node")], target: main, lock: lock)
        XCTAssertEqual(s["node"], .pendingRemove)
    }

    func testNeedsOfDeclaredAreDependencies() {
        let lock = PackagesLock(machines: ["main": [.init(name: "essentials"), .init(name: "caddy")]])
        let entries = [entry("essentials", needs: ["caddy"], on: ["machine main"]), entry("caddy")]
        let s = PackageStatusCheck.evaluate(entries: entries, target: main, lock: lock)
        XCTAssertEqual(s["caddy"], .appliedAsDependency(of: "essentials"))
    }

    func testDependencyNotLockedIsPendingInstall() {
        let entries = [entry("essentials", needs: ["caddy"], on: ["machine main"]), entry("caddy")]
        let s = PackageStatusCheck.evaluate(entries: entries, target: main, lock: PackagesLock(machines: [:]))
        XCTAssertEqual(s["caddy"], .pendingInstall)
    }

    func testNotDeclaredNotLockedIsAvailable() {
        let s = PackageStatusCheck.evaluate(entries: [entry("docker")], target: main, lock: PackagesLock(machines: [:]))
        XCTAssertEqual(s["docker"], .available)
    }

    func testNilLockReadsDeclaredAsApplied() {
        let s = PackageStatusCheck.evaluate(entries: [entry("docker", on: ["machine main"]), entry("node")],
                                            target: main, lock: nil)
        XCTAssertEqual(s["docker"], .applied)
        XCTAssertEqual(s["node"], .available)
    }

    func testWorkspaceTargetReadsWorkspaceLockAndAccountPackage() {
        let acme = PackageTarget.workspace("acme", machine: "main")
        let lock = PackagesLock(machines: [:], workspaces: ["acme": [.init(name: "workspace"), .init(name: "node")]])
        let entries = [entry("workspace", scope: "workspace"), entry("node", scope: "workspace", on: ["workspace acme"])]
        let s = PackageStatusCheck.evaluate(entries: entries, target: acme, lock: lock)
        XCTAssertEqual(s["node"], .applied)
        XCTAssertEqual(s["workspace"], .appliedAsDependency(of: "workspace"))
    }

    func testMachineNeedsOfWorkspacePackagesAreDependencies() {
        let lock = PackagesLock(machines: ["main": [.init(name: "docker")]])
        let entries = [entry("docker"), entry("compose-dev", scope: "workspace", needs: ["docker"], on: ["workspace acme"])]
        let s = PackageStatusCheck.evaluate(entries: entries, target: main, lock: lock, workspacesOnMachine: ["acme"])
        XCTAssertEqual(s["docker"], .appliedAsDependency(of: "compose-dev"))
    }

    func testLockedNameWithNoEntryIsPendingRemove() {
        let lock = PackagesLock(machines: ["main": [.init(name: "docker"), .init(name: "gone")]])
        let s = PackageStatusCheck.evaluate(entries: [entry("docker", on: ["machine main"])], target: main, lock: lock)
        XCTAssertEqual(s["gone"], .pendingRemove)
        XCTAssertEqual(s["docker"], .applied)
    }
}
