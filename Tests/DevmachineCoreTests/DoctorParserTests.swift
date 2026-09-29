import XCTest
@testable import DevmachineCore

final class DoctorParserTests: XCTestCase {
    func testParsesEveryStatusFromJSON() throws {
        let output = """
        {
          "checks": [
            {"name": "configuration", "status": "pass", "detail": "machine \\"box\\", 1 address(es)"},
            {"name": "ssh aliases", "status": "warn", "detail": "stale: run `devmachine aliases --write`"},
            {"name": "connection", "status": "fail", "detail": "run `devmachine machines trust box`"},
            {"name": "ansible", "status": "skip", "detail": "the machine is unreachable"}
          ],
          "ok": false
        }
        """

        let report = try XCTUnwrap(DoctorParser.parse(output))

        XCTAssertEqual(report.ok, false)
        XCTAssertEqual(report.checks, [
            DoctorCheck(name: "configuration", status: .pass, detail: "machine \"box\", 1 address(es)"),
            DoctorCheck(name: "ssh aliases", status: .warn, detail: "stale: run `devmachine aliases --write`"),
            DoctorCheck(name: "connection", status: .fail, detail: "run `devmachine machines trust box`"),
            DoctorCheck(name: "ansible", status: .skip, detail: "the machine is unreachable"),
        ])
    }

    func testAllPassingReportsOK() throws {
        let output = #"{"checks":[{"name":"configuration","status":"pass","detail":"ok"}],"ok":true}"#

        let report = try XCTUnwrap(DoctorParser.parse(output))

        XCTAssertTrue(report.ok)
    }

    func testAnUnrecognizedStatusIsReadAsFailNeverAsASilentPass() throws {
        let output = #"{"checks":[{"name":"configuration","status":"mystery","detail":""}],"ok":true}"#

        let report = try XCTUnwrap(DoctorParser.parse(output))

        XCTAssertEqual(report.checks.first?.status, .fail)
    }

    func testFallsBackToTheCLIsPlainTextTable() throws {
        let output = """
        pass  configuration        machine "box", 1 address(es), admin ops, port 22, 2 workspace(s)
        warn  ssh aliases          stale: run `devmachine aliases --write`
        fail  connection           dial tcp 203.0.113.10:22: connect: connection refused
        skip  operating system     the machine is unreachable
        """

        let report = try XCTUnwrap(DoctorParser.parse(output))

        XCTAssertEqual(report.checks, [
            DoctorCheck(
                name: "configuration",
                status: .pass,
                detail: "machine \"box\", 1 address(es), admin ops, port 22, 2 workspace(s)"),
            DoctorCheck(name: "ssh aliases", status: .warn, detail: "stale: run `devmachine aliases --write`"),
            DoctorCheck(
                name: "connection", status: .fail,
                detail: "dial tcp 203.0.113.10:22: connect: connection refused"),
            DoctorCheck(name: "operating system", status: .skip, detail: "the machine is unreachable"),
        ])
        XCTAssertFalse(report.ok)
    }

    func testTextTableWithNoDetailStillParses() throws {
        let output = "pass  bundle\n"

        let report = try XCTUnwrap(DoctorParser.parse(output))

        XCTAssertEqual(report.checks, [DoctorCheck(name: "bundle", status: .pass, detail: "")])
    }

    func testUnparseableOutputReturnsNil() {
        XCTAssertNil(DoctorParser.parse("the machine could not be reached at all"))
        XCTAssertNil(DoctorParser.parse(""))
    }
}
