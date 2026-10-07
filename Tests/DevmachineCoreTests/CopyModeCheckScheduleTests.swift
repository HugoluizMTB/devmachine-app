import XCTest
@testable import DevmachineCore

final class CopyModeCheckScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let machines = ["acme-devmachine": "main", "beta-devmachine": "main", "gamma-devmachine": "backup"]

    private func due(
        _ schedule: inout CopyModeCheckSchedule, at now: Date, paused: Set<String> = [], sweeping: Bool = false,
        panes: [(alias: String, session: String)]? = nil
    ) -> [CopyModeCheck] {
        schedule.due(
            panes: panes ?? [
                ("beta-devmachine", "main"), ("acme-devmachine", "dash"), ("acme-devmachine", "api"),
                ("gamma-devmachine", "web"),
            ],
            machine: { self.machines[$0] }, now: now, isPaused: { paused.contains($0) }, sweeping: sweeping)
    }

    func testEachAccountOnScreenIsCheckedOnceGroupedByMachine() {
        var schedule = CopyModeCheckSchedule()

        let checks = due(&schedule, at: start)

        XCTAssertEqual(checks.map(\.machine), ["backup", "main", "main"])
        XCTAssertEqual(checks.map(\.alias), ["gamma-devmachine", "acme-devmachine", "beta-devmachine"])
        XCTAssertEqual(
            checks[1].command,
            RemoteCommands.leaveIdleCopyMode(session: "api") + "; " + RemoteCommands.leaveIdleCopyMode(session: "dash"))
    }

    func testAMachineIsCheckedAtMostOncePerInterval() {
        var schedule = CopyModeCheckSchedule(interval: 300)
        _ = due(&schedule, at: start)

        XCTAssertTrue(due(&schedule, at: start.addingTimeInterval(299)).isEmpty)
        XCTAssertEqual(due(&schedule, at: start.addingTimeInterval(300)).count, 3)
    }

    func testAMachineNotCheckedYetIsStillDueWhileAnotherWaits() {
        var schedule = CopyModeCheckSchedule(interval: 300)
        _ = due(&schedule, at: start, panes: [("acme-devmachine", "dash")])

        let checks = due(&schedule, at: start.addingTimeInterval(10))

        XCTAssertEqual(checks.map(\.machine), ["backup"])
    }

    func testNothingRunsWhileTheSweepRunsAndNothingIsSpent() {
        var schedule = CopyModeCheckSchedule()

        XCTAssertTrue(due(&schedule, at: start, sweeping: true).isEmpty)
        XCTAssertEqual(due(&schedule, at: start).count, 3)
    }

    func testAPausedWorkspaceIsLeftOutAndSpendsNothingForItsMachine() {
        var schedule = CopyModeCheckSchedule()

        let checks = due(&schedule, at: start, paused: ["acme-devmachine", "gamma-devmachine"])
        XCTAssertEqual(checks.map(\.alias), ["beta-devmachine"])

        let later = due(&schedule, at: start.addingTimeInterval(10))
        XCTAssertEqual(later.map(\.alias), ["gamma-devmachine"])
    }

    func testAnAliasWithNoKnownMachineCountsAsItsOwn() {
        var schedule = CopyModeCheckSchedule()

        let checks = schedule.due(
            panes: [("delta-devmachine", "x")], machine: { _ in nil }, now: start, isPaused: { _ in false }, sweeping: false)

        XCTAssertEqual(checks.map(\.machine), ["delta-devmachine"])
    }
}
