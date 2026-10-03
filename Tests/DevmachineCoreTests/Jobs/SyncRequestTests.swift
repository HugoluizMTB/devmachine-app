import XCTest
@testable import DevmachineCore

final class SyncRequestTests: XCTestCase {
    func testNoTagsMeansFull() {
        XCTAssertTrue(SyncRequest(machine: "main").full)
    }

    func testMergeUnionsTagsAndReasonsInOrder() {
        let a = SyncRequest(machine: "main", tags: ["docker", "node"], reasons: ["Packages"])
        let b = SyncRequest(machine: "main", tags: ["node", "caddy"], reasons: ["DNS"])
        let merged = a.merging(b)
        XCTAssertEqual(merged.tags, ["docker", "node", "caddy"])
        XCTAssertEqual(merged.reasons, ["Packages", "DNS"])
        XCTAssertFalse(merged.full)
    }

    func testFullWinsOnMerge() {
        let merged = SyncRequest(machine: "main", tags: ["docker"])
            .merging(SyncRequest(machine: "main", tags: ["node"], full: true))
        XCTAssertTrue(merged.full)
    }

    func testMergeIgnoresAnotherMachine() {
        let a = SyncRequest(machine: "main", tags: ["docker"])
        XCTAssertEqual(a.merging(SyncRequest(machine: "dev", tags: ["node"])), a)
    }

    func testArguments() {
        let r = SyncRequest(machine: "main", tags: ["docker", "node"])
        XCTAssertEqual(r.arguments(full: false), ["sync", "--machine", "main", "--tags", "docker,node", "--yes"])
        XCTAssertEqual(r.arguments(full: true), ["sync", "--machine", "main", "--yes"])
    }

    func testStartsFullOnOldCLIOrFullRequest() {
        let tagged = SyncRequest(machine: "main", tags: ["docker"])
        XCTAssertFalse(tagged.startsFull(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 24)))
        XCTAssertTrue(tagged.startsFull(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 23)))
        XCTAssertTrue(tagged.startsFull(cliVersion: nil))
        XCTAssertTrue(SyncRequest(machine: "main", tags: ["docker"], full: true)
            .startsFull(cliVersion: SemanticVersion(major: 0, minor: 8, patch: 0)))
    }
}
