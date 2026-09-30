import XCTest
@testable import DevmachineCore

private func sampleSnapshot(load1: Double = 0.5) -> StatsSnapshot {
    StatsSnapshot(
        collectedAt: "2026-09-29T16:23:11+00:00",
        memory: .init(totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, availableBytes: 8_000_000_000),
        swap: .init(totalBytes: 0, usedBytes: 0),
        disk: .init(path: "/", usedBytes: 40_000_000_000, availableBytes: 60_000_000_000, usedPercent: 40),
        load: .init(load1: load1, load5: 0.4, load15: 0.3),
        docker: .init(available: true, containers: [
            ContainerStat(name: "postgres", memUsedBytes: 512_000_000, memLimitBytes: 0, cpuPercent: 1.5, owner: "alice"),
        ]),
        users: [UserRAM(user: "alice", rssBytes: 1_000_000_000)],
        ports: [PortOwner(port: 3000, owner: "alice")],
        errors: [])
}

final class StatsCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatsCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var cache: StatsCache {
        StatsCache(fileURL: directory.appendingPathComponent("stats-cache.json"))
    }

    func testWhatIsSavedIsReadBackInTheSameOrder() throws {
        let collectedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let entries = [
            CachedMachineStats(machine: "beta", firstAddress: "203.0.113.11", collectedAt: collectedAt, snapshot: sampleSnapshot(load1: 2)),
            CachedMachineStats(machine: "acme", firstAddress: nil, collectedAt: collectedAt, snapshot: sampleSnapshot(load1: 1)),
        ]

        try cache.save(entries)

        XCTAssertEqual(cache.load(), entries)
    }

    func testAMissingFileReadsAsEmpty() {
        XCTAssertEqual(cache.load(), [])
    }

    func testACorruptFileIsIgnored() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: cache.fileURL)

        XCTAssertEqual(cache.load(), [])
    }

    func testAFileFromAnotherVersionIsIgnored() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version": 999, "machines": []}"#.utf8).write(to: cache.fileURL)

        XCTAssertEqual(cache.load(), [])
    }

    func testTheFileCarriesCollectedAtForEachMachine() throws {
        let collectedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try cache.save([CachedMachineStats(machine: "acme", firstAddress: nil, collectedAt: collectedAt, snapshot: sampleSnapshot())])

        let text = try String(contentsOf: cache.fileURL, encoding: .utf8)

        XCTAssertTrue(text.contains("\"collectedAt\""))
        XCTAssertTrue(text.contains("\"machine\" : \"acme\""))
    }
}
