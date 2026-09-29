import XCTest
@testable import DevmachineCore

final class StatsParserTests: XCTestCase {
    func testParsesFullSample() throws {
        let output = """
        {
          "collected_at": "2026-09-29T16:23:11+00:00",
          "memory": {"total_bytes": 33554432000, "used_bytes": 12345678000, "available_bytes": 20000000000},
          "swap": {"total_bytes": 8589934592, "used_bytes": 1048576},
          "disk": {"path": "/", "used_bytes": 123450000000, "available_bytes": 67890000000, "used_percent": 73},
          "load": {"load1": 0.52, "load5": 0.48, "load15": 0.44},
          "docker": {
            "available": true,
            "containers": [
              {"name": "beta-pg", "mem_used_bytes": 129394688, "mem_limit_bytes": 2086027264, "cpu_percent": 0.05, "owner": "beta"},
              {"name": "agents-api", "mem_used_bytes": 2255536947, "mem_limit_bytes": 33604517888, "cpu_percent": 12.3, "owner": null}
            ]
          },
          "users": [
            {"user": "acme", "rss_bytes": 4194304},
            {"user": "root", "rss_bytes": 2097152},
            {"user": "dev", "rss_bytes": 1048576}
          ],
          "ports": [
            {"port": 8810, "owner": "acme"},
            {"port": 22, "owner": "root"}
          ],
          "errors": []
        }
        """

        let snapshot = try XCTUnwrap(StatsParser.parse(output))

        XCTAssertEqual(snapshot.memory, StatsSnapshot.Memory(
            totalBytes: 33554432000, usedBytes: 12345678000, availableBytes: 20000000000))
        XCTAssertEqual(snapshot.swap, StatsSnapshot.Swap(totalBytes: 8589934592, usedBytes: 1048576))
        XCTAssertEqual(snapshot.disk, StatsSnapshot.Disk(
            path: "/", usedBytes: 123450000000, availableBytes: 67890000000, usedPercent: 73))
        XCTAssertEqual(snapshot.load, StatsSnapshot.Load(load1: 0.52, load5: 0.48, load15: 0.44))
        XCTAssertTrue(snapshot.docker.available)
        XCTAssertEqual(snapshot.containers, [
            ContainerStat(name: "beta-pg", memUsedBytes: 129394688, memLimitBytes: 2086027264, cpuPercent: 0.05, owner: "beta"),
            ContainerStat(name: "agents-api", memUsedBytes: 2255536947, memLimitBytes: 33604517888, cpuPercent: 12.3, owner: nil)
        ])
        XCTAssertEqual(snapshot.users, [
            UserRAM(user: "acme", rssBytes: 4194304),
            UserRAM(user: "root", rssBytes: 2097152),
            UserRAM(user: "dev", rssBytes: 1048576)
        ])
        XCTAssertEqual(snapshot.ports, [
            PortOwner(port: 8810, owner: "acme"),
            PortOwner(port: 22, owner: "root")
        ])
        XCTAssertEqual(snapshot.errors, [])
    }

    func testDockerUnavailableYieldsNoContainersButStillParses() throws {
        let output = """
        {
          "collected_at": "2026-09-29T16:23:11+00:00",
          "memory": {"total_bytes": 1, "used_bytes": 0, "available_bytes": 1},
          "swap": {"total_bytes": 0, "used_bytes": 0},
          "disk": {"path": "/", "used_bytes": 0, "available_bytes": 0, "used_percent": 0},
          "load": {"load1": 0, "load5": 0, "load15": 0},
          "docker": {"available": false, "containers": []},
          "users": [],
          "ports": [],
          "errors": ["docker: command not found"]
        }
        """

        let snapshot = try XCTUnwrap(StatsParser.parse(output))
        XCTAssertFalse(snapshot.docker.available)
        XCTAssertEqual(snapshot.containers, [])
        XCTAssertEqual(snapshot.errors, ["docker: command not found"])
    }

    func testEmptyOutputYieldsNoSnapshot() {
        XCTAssertNil(StatsParser.parse(""))
    }

    func testWhitespaceOnlyOutputYieldsNoSnapshot() {
        XCTAssertNil(StatsParser.parse("  \n  "))
    }

    func testInvalidJSONYieldsNoSnapshot() {
        XCTAssertNil(StatsParser.parse("not json"))
    }

    func testTruncatedJSONYieldsNoSnapshot() {
        XCTAssertNil(StatsParser.parse(#"{"memory": {"total_bytes": 1}"#))
    }
}
