import XCTest
@testable import DevmachineCore

final class PackageSelectionTests: XCTestCase {
    private let main = PackageTarget.machine("main", isSelf: false)

    func testChangesSplitByStatus() {
        var selection = PackageSelection()
        selection.toggle("docker")
        selection.toggle("node")
        selection.toggle("old")
        let statuses: [String: PackageStatus] = ["docker": .available, "node": .applied, "old": .pendingRemove]
        let changes = selection.changes(statuses: statuses)
        XCTAssertEqual(changes.adds, ["docker", "old"])
        XCTAssertEqual(changes.removes, ["node"])
    }

    func testToggleTwiceUnselects() {
        var selection = PackageSelection()
        selection.toggle("docker")
        selection.toggle("docker")
        XCTAssertTrue(selection.names.isEmpty)
    }

    func testCommandsAddsThenRemoves() {
        let changes = PackageChanges(adds: ["docker"], removes: ["node"])
        XCTAssertEqual(changes.commands(target: main), [
            ["packages", "add", "docker", "--machine", "main", "--yes"],
            ["packages", "rm", "node", "--machine", "main", "--yes"],
        ])
        let acme = PackageTarget.workspace("acme", machine: "main")
        XCTAssertEqual(PackageChanges(adds: ["node"], removes: []).commands(target: acme),
                       [["packages", "add", "node", "--workspace", "acme", "--yes"]])
    }

    func testSyncRequestTaggedForAddsFullForRemoves() {
        XCTAssertEqual(PackageChanges(adds: ["docker"], removes: []).syncRequest(target: main),
                       SyncRequest(machine: "main", tags: ["docker"], reasons: ["Packages"]))
        XCTAssertTrue(PackageChanges(adds: ["docker"], removes: ["node"]).syncRequest(target: main)!.full)
        let acme = PackageTarget.workspace("acme", machine: "dev")
        XCTAssertEqual(PackageChanges(adds: ["node"], removes: []).syncRequest(target: acme)?.machine, "dev")
        XCTAssertNil(PackageChanges(adds: [], removes: []).syncRequest(target: main))
    }

    func testPendingSyncRequest() {
        let statuses: [String: PackageStatus] = ["docker": .pendingInstall, "node": .applied]
        XCTAssertEqual(PackagePending.syncRequest(statuses: statuses, target: main),
                       SyncRequest(machine: "main", tags: ["docker"], reasons: ["Packages"]))
        XCTAssertTrue(PackagePending.syncRequest(statuses: ["x": .pendingRemove], target: main)!.full)
        XCTAssertNil(PackagePending.syncRequest(statuses: ["node": .applied], target: main))
    }
}
