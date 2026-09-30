import XCTest
@testable import DevmachineCore

final class StatsPollScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let policy = StatsPollPolicy(interval: 90, backoff: [90, 180, 300], stagger: 3)

    func testNewMachinesWithoutCacheAreStaggeredFromNow() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme", "beta", "gamma"], lastSuccess: [:], now: start)

        XCTAssertEqual(schedule.due(now: start), ["acme"])
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(3)), ["acme", "beta"])
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(6)), ["acme", "beta", "gamma"])
    }

    func testAFreshCacheWaitsForTheIntervalFromItsCollectedTime() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme"], lastSuccess: ["acme": start.addingTimeInterval(-30)], now: start)

        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(59)), [])
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(60)), ["acme"])
    }

    func testAnOldCacheIsDueAtOnce() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme"], lastSuccess: ["acme": start.addingTimeInterval(-600)], now: start)

        XCTAssertEqual(schedule.due(now: start), ["acme"])
    }

    func testOnlyOneRunPerMachineIsInFlight() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme"], lastSuccess: [:], now: start)

        XCTAssertTrue(schedule.begin("acme"))
        XCTAssertFalse(schedule.begin("acme"))
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(1_000)), [])
    }

    func testASuccessSchedulesTheNextRunOneIntervalLater() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme"], lastSuccess: [:], now: start)
        _ = schedule.begin("acme")

        schedule.succeed("acme", now: start)

        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(89)), [])
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(90)), ["acme"])
    }

    func testFailuresBackOffUpToTheLongestDelay() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme"], lastSuccess: [:], now: start)
        var now = start
        var delays: [TimeInterval] = []
        for _ in 0..<5 {
            _ = schedule.begin("acme")
            schedule.fail("acme", now: now)
            let next = schedule.nextDue("acme")!
            delays.append(next.timeIntervalSince(now))
            now = next
        }

        XCTAssertEqual(delays, [90, 180, 300, 300, 300])
    }

    func testASuccessAfterFailuresResetsTheBackoff() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme"], lastSuccess: [:], now: start)
        _ = schedule.begin("acme")
        schedule.fail("acme", now: start)
        _ = schedule.begin("acme")
        schedule.fail("acme", now: start)
        _ = schedule.begin("acme")
        schedule.succeed("acme", now: start)
        _ = schedule.begin("acme")
        schedule.fail("acme", now: start)

        XCTAssertEqual(schedule.nextDue("acme"), start.addingTimeInterval(90))
    }

    func testRefreshAllMakesEveryMachineDueNowStaggeredAndClearsTheBackoff() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme", "beta"], lastSuccess: [:], now: start)
        for name in ["acme", "beta"] {
            _ = schedule.begin(name)
            schedule.fail(name, now: start)
            _ = schedule.begin(name)
            schedule.fail(name, now: start)
        }
        let later = start.addingTimeInterval(10)

        schedule.refreshAll(now: later, first: "beta")

        XCTAssertEqual(schedule.due(now: later), ["beta"])
        XCTAssertEqual(schedule.due(now: later.addingTimeInterval(3)), ["acme", "beta"])
        _ = schedule.begin("beta")
        schedule.fail("beta", now: later)
        XCTAssertEqual(schedule.nextDue("beta"), later.addingTimeInterval(90))
    }

    func testRemovedMachinesLeaveTheSchedule() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme", "beta"], lastSuccess: [:], now: start)

        schedule.setMachines(["beta"], lastSuccess: [:], now: start)

        XCTAssertNil(schedule.nextDue("acme"))
        XCTAssertEqual(schedule.machines, ["beta"])
    }

    func testKeepingAMachineKeepsItsPlaceInTheSchedule() {
        var schedule = StatsPollSchedule(policy: policy)
        schedule.setMachines(["acme"], lastSuccess: [:], now: start)
        _ = schedule.begin("acme")
        schedule.succeed("acme", now: start)

        schedule.setMachines(["acme", "beta"], lastSuccess: [:], now: start.addingTimeInterval(5))

        XCTAssertEqual(schedule.nextDue("acme"), start.addingTimeInterval(90))
        XCTAssertTrue(schedule.isInFlight("acme") == false)
    }
}

final class StatsFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testAgeText() {
        XCTAssertEqual(StatsFreshness.ageText(since: now.addingTimeInterval(-20), now: now), "updated just now")
        XCTAssertEqual(StatsFreshness.ageText(since: now.addingTimeInterval(-60), now: now), "updated 1m ago")
        XCTAssertEqual(StatsFreshness.ageText(since: now.addingTimeInterval(-59 * 60), now: now), "updated 59m ago")
        XCTAssertEqual(StatsFreshness.ageText(since: now.addingTimeInterval(-2 * 3600), now: now), "updated 2h ago")
        XCTAssertEqual(StatsFreshness.ageText(since: now.addingTimeInterval(-3 * 86_400), now: now), "updated 3d ago")
        XCTAssertEqual(StatsFreshness.ageText(since: now.addingTimeInterval(30), now: now), "updated just now")
    }

    func testStaleAfterAFewMissedPolls() {
        XCTAssertFalse(StatsFreshness.isStale(since: now.addingTimeInterval(-299), now: now))
        XCTAssertTrue(StatsFreshness.isStale(since: now.addingTimeInterval(-301), now: now))
    }
}
