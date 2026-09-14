import XCTest
@testable import DevmachineCore

final class StatsParserTests: XCTestCase {
    func testParsesFullSample() {
        let output = """
        @@MEM@@
        33554432000 12345678000 20000000000
        @@SWAP@@
        8589934592 1048576
        @@DISK@@
        123450000000 67890000000 73%
        @@LOAD@@
        0.52 0.48 0.44 2/1234 56789
        @@DOCKER@@
        beta-pg|123.4MiB / 31.3GiB|0.05%
        agents-api|2.1GiB / 31.3GiB|12.30%
        @@USERS@@
        root 2048
        acme 4096
        dev 1024
        """

        let snapshot = StatsParser.parse(output)

        XCTAssertEqual(snapshot, StatsSnapshot(
            memTotal: 33554432000,
            memUsed: 12345678000,
            memAvailable: 20000000000,
            swapTotal: 8589934592,
            swapUsed: 1048576,
            diskUsed: 123450000000,
            diskAvail: 67890000000,
            diskPercent: 73,
            load1: 0.52,
            load5: 0.48,
            load15: 0.44,
            containers: [
                ContainerStat(name: "beta-pg", mem: "123.4MiB / 31.3GiB", cpu: "0.05%"),
                ContainerStat(name: "agents-api", mem: "2.1GiB / 31.3GiB", cpu: "12.30%")
            ],
            users: [
                UserRAM(user: "acme", rssBytes: 4096 * 1024),
                UserRAM(user: "root", rssBytes: 2048 * 1024),
                UserRAM(user: "dev", rssBytes: 1024 * 1024)
            ]
        ))
    }

    func testTruncatedOutputYieldsZerosAndEmptiesWithoutCrashing() {
        let output = """
        @@MEM@@
        33554432000 12345678000 20000000000
        @@DISK@@
        123450000000 67890000000 73%
        """

        let snapshot = StatsParser.parse(output)

        XCTAssertEqual(snapshot.memTotal, 33554432000)
        XCTAssertEqual(snapshot.memUsed, 12345678000)
        XCTAssertEqual(snapshot.memAvailable, 20000000000)
        XCTAssertEqual(snapshot.swapTotal, 0)
        XCTAssertEqual(snapshot.swapUsed, 0)
        XCTAssertEqual(snapshot.diskUsed, 123450000000)
        XCTAssertEqual(snapshot.diskAvail, 67890000000)
        XCTAssertEqual(snapshot.diskPercent, 73)
        XCTAssertEqual(snapshot.load1, 0)
        XCTAssertEqual(snapshot.load5, 0)
        XCTAssertEqual(snapshot.load15, 0)
        XCTAssertEqual(snapshot.containers, [])
        XCTAssertEqual(snapshot.users, [])
    }

    func testEmptyOutputNeverCrashes() {
        let snapshot = StatsParser.parse("")

        XCTAssertEqual(snapshot, StatsSnapshot(
            memTotal: 0, memUsed: 0, memAvailable: 0,
            swapTotal: 0, swapUsed: 0,
            diskUsed: 0, diskAvail: 0, diskPercent: 0,
            load1: 0, load5: 0, load15: 0,
            containers: [], users: []
        ))
    }

    func testDiskPercentStripsTrailingPercentSign() {
        let output = """
        @@DISK@@
        1 2 73%
        """

        XCTAssertEqual(StatsParser.parse(output).diskPercent, 73)
    }

    func testUserRSSConvertsKilobytesToBytes() {
        let output = """
        @@USERS@@
        root 2048
        """

        let users = StatsParser.parse(output).users
        XCTAssertEqual(users, [UserRAM(user: "root", rssBytes: 2097152)])
    }

    func testRemoteCommandsStatsSnapshotString() {
        let expected = "echo '@@MEM@@'; free -b | awk 'NR==2{print $2, $3, $7}'; echo '@@SWAP@@'; free -b | awk 'NR==3{print $2, $3}'; echo '@@DISK@@'; df -B1 --output=used,avail,pcent / | tail -1; echo '@@LOAD@@'; cat /proc/loadavg; echo '@@DOCKER@@'; docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}|{{.CPUPerc}}'; echo '@@USERS@@'; ps -eo user=,rss= | awk '{a[$1]+=$2} END{for (u in a) print u, a[u]}'"

        XCTAssertEqual(RemoteCommands.statsSnapshot, expected)
    }
}
