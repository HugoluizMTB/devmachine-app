import XCTest
import DevmachineCore
@testable import DevmachineApp

final class MachineCardSummaryTests: XCTestCase {
    private func snapshot(total: Int64, used: Int64) -> StatsSnapshot {
        StatsSnapshot(
            collectedAt: "2026-09-29T16:23:11+00:00",
            memory: .init(totalBytes: total, usedBytes: used, availableBytes: total - used),
            swap: .init(totalBytes: 0, usedBytes: 0),
            disk: .init(path: "/", usedBytes: 0, availableBytes: 116_000_000_000, usedPercent: 42),
            load: .init(load1: 1.234, load5: 0, load15: 0),
            docker: .init(available: true, containers: []),
            users: [], ports: [], errors: [])
    }

    func testTheCardShowsRamPercentDiskFreeLoadAndContainers() {
        let summary = MachineCardSummary(snapshot: snapshot(total: 16_000, used: 9_600), containerCount: 4)

        XCTAssertEqual(summary.ram, "60%")
        XCTAssertEqual(summary.diskFree, "108.0 GB")
        XCTAssertEqual(summary.load1, "1.23")
        XCTAssertEqual(summary.containers, "4")
    }

    func testAMachineWithNoMemoryTotalShowsADash() {
        XCTAssertEqual(MachineCardSummary(snapshot: snapshot(total: 0, used: 0), containerCount: 0).ram, "--")
    }
}

