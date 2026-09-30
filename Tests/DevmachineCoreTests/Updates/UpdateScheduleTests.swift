import XCTest
@testable import DevmachineCore

final class UpdateScheduleTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 1_790_000_000)
    private let schedule = UpdateSchedule()

    func testTheFirstCheckWaitsThirtySecondsAfterLaunch() {
        XCTAssertEqual(schedule.nextCheck(launchedAt: launch, lastCheckedAt: nil), launch.addingTimeInterval(30))
        XCTAssertFalse(schedule.isDue(now: launch.addingTimeInterval(29), launchedAt: launch, lastCheckedAt: nil))
        XCTAssertTrue(schedule.isDue(now: launch.addingTimeInterval(30), launchedAt: launch, lastCheckedAt: nil))
    }

    func testThenEverySixHoursAfterTheLastCheck() {
        let checked = launch.addingTimeInterval(30)
        XCTAssertEqual(
            schedule.nextCheck(launchedAt: launch, lastCheckedAt: checked),
            checked.addingTimeInterval(6 * 3600))
        XCTAssertFalse(schedule.isDue(
            now: checked.addingTimeInterval(6 * 3600 - 1), launchedAt: launch, lastCheckedAt: checked))
        XCTAssertTrue(schedule.isDue(
            now: checked.addingTimeInterval(6 * 3600), launchedAt: launch, lastCheckedAt: checked))
    }

    func testAManualCheckRightAfterLaunchStillLetsTheLaunchDelayPass() {
        let manual = launch.addingTimeInterval(5)
        XCTAssertEqual(
            schedule.nextCheck(launchedAt: launch, lastCheckedAt: manual),
            manual.addingTimeInterval(6 * 3600))
    }

    func testDelayIsNeverNegative() {
        XCTAssertEqual(schedule.delay(now: launch.addingTimeInterval(100), launchedAt: launch, lastCheckedAt: nil), 0)
        XCTAssertEqual(schedule.delay(now: launch, launchedAt: launch, lastCheckedAt: nil), 30)
    }
}
