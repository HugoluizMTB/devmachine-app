import XCTest
@testable import DevmachineCore

final class LocalSessionScanTests: XCTestCase {
    private func live(_ name: String, pid: Int = 1, directory: String? = nil) -> ZmxSession {
        ZmxSession(name: name, pid: pid, clients: 1, directory: directory)
    }

    func testRememberedSessionsKeepTheirOrderAndFolder() {
        let stored = [
            LocalSession(name: "Operator", path: "/Users/alice/ops"),
            LocalSession(name: "acme", path: "/Users/alice/dev/acme"),
        ]
        let merged = LocalSessionScan.merge(
            stored: stored, live: [live("acme", directory: "/elsewhere")],
            fallbackPath: "/Users/alice")

        XCTAssertEqual(merged.map(\.handle), ["Operator", "acme"])
        XCTAssertEqual(merged.last?.path, "/Users/alice/dev/acme")
    }

    func testASessionOnlyTheMultiplexerKnowsIsAppended() {
        let merged = LocalSessionScan.merge(
            stored: [LocalSession(name: "Operator", path: "/ops")],
            live: [live("Operator"), live("stray", directory: "/Users/alice/dev/stray")],
            fallbackPath: "/Users/alice")

        XCTAssertEqual(merged.map(\.handle), ["Operator", "stray"])
        XCTAssertEqual(merged.last?.path, "/Users/alice/dev/stray")
    }

    func testAStraySessionWithoutAFolderFallsBack() {
        let merged = LocalSessionScan.merge(
            stored: [], live: [live("stray")], fallbackPath: "/Users/alice")
        XCTAssertEqual(merged.first?.path, "/Users/alice")
    }

    func testARenamedSessionIsStillMatchedByItsHandle() {
        let stored = [LocalSession(handle: "acme", name: "Client work", path: "/dev/acme")]
        let merged = LocalSessionScan.merge(
            stored: stored, live: [live("acme")], fallbackPath: "/Users/alice")

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.name, "Client work")
    }
}
