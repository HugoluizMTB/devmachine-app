import XCTest
@testable import DevmachineCore

final class JobProgressLineTests: XCTestCase {
    private let plan = [
        "$ devmachine sync --machine main --tags heroku --yes",
        "machine main:", "  caddy", "workspace acme (user acme):", "  heroku",
        "extensions:", "  caddy-sites -> caddy.sites.d (/etc/caddy/sites.d)",
    ]

    func testASyncStillPrintingItsPlanSaysItIsPlanning() {
        XCTAssertEqual(JobProgressLine.current(lines: plan, isSync: true, machine: "main"), "Planning the sync on main…")
    }

    func testASyncRunningAnsibleShowsTheCurrentTask() {
        let lines = plan + ["", "PLAY [devmachine] ****", "TASK [Gathering Facts] ****", "ok: [devmachine]",
                            "TASK [heroku : Install the Heroku CLI] *********", "changed: [devmachine]"]
        XCTAssertEqual(
            JobProgressLine.current(lines: lines, isSync: true, machine: "main"), "heroku : Install the Heroku CLI")
    }

    func testASyncBetweenThePlayAndItsFirstTaskIsStarting() {
        XCTAssertEqual(
            JobProgressLine.current(lines: plan + ["PLAY [devmachine] ****"], isSync: true, machine: "main"),
            "Starting the sync on main…")
    }

    func testAnyOtherJobShowsItsLastLine() {
        XCTAssertEqual(
            JobProgressLine.current(lines: ["checking", "** reading zones **"], isSync: false, machine: "main"),
            "reading zones")
        XCTAssertNil(JobProgressLine.current(lines: [], isSync: false, machine: "main"))
    }
}
