import XCTest
@testable import DevmachineCore

final class WidgetRuntimeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let claude = WidgetRefreshKey(provider: "app/harness-usage", args: ["harness": "claude"])
    private let clock = WidgetRefreshKey(provider: "app/clock", args: [:])

    func testANewJobIsDueAtOnceThenWaitsItsInterval() {
        var runtime = WidgetRuntime()
        runtime.replaceJobs([WidgetJob(instanceID: "u", key: claude, every: 60, isActive: true)])
        XCTAssertEqual(runtime.due(now: start), [claude])
        runtime.markRan([claude], at: start)
        XCTAssertEqual(runtime.due(now: start.addingTimeInterval(59)), [])
        XCTAssertEqual(runtime.due(now: start.addingTimeInterval(60)), [claude])
    }

    func testAMinimizedWidgetIsNeverDue() {
        var runtime = WidgetRuntime()
        runtime.replaceJobs([WidgetJob(instanceID: "u", key: claude, every: 60, isActive: false)])
        XCTAssertEqual(runtime.due(now: start), [])
        XCTAssertFalse(runtime.hasActiveJobs)
    }

    func testTwoInstancesOfOneCallRefreshOnceAtTheShorterInterval() {
        var runtime = WidgetRuntime()
        runtime.replaceJobs([
            WidgetJob(instanceID: "a", key: claude, every: 60, isActive: true),
            WidgetJob(instanceID: "b", key: claude, every: 30, isActive: true),
        ])
        XCTAssertEqual(runtime.due(now: start), [claude])
        runtime.markRan([claude], at: start)
        XCTAssertEqual(runtime.due(now: start.addingTimeInterval(30)), [claude])
    }

    func testReplacingJobsKeepsWhatAlreadyRan() {
        var runtime = WidgetRuntime()
        runtime.replaceJobs([WidgetJob(instanceID: "u", key: claude, every: 60, isActive: true)])
        runtime.markRan([claude], at: start)
        runtime.replaceJobs([
            WidgetJob(instanceID: "u", key: claude, every: 60, isActive: true),
            WidgetJob(instanceID: "c", key: clock, every: 5, isActive: true),
        ])
        XCTAssertEqual(runtime.due(now: start.addingTimeInterval(1)), [clock])
        runtime.replaceJobs([])
        runtime.replaceJobs([WidgetJob(instanceID: "u", key: claude, every: 60, isActive: true)])
        XCTAssertEqual(runtime.due(now: start.addingTimeInterval(1)), [claude])
    }

    func testDueKeysComeInAStableOrder() {
        var runtime = WidgetRuntime()
        runtime.replaceJobs([
            WidgetJob(instanceID: "u", key: claude, every: 60, isActive: true),
            WidgetJob(instanceID: "c", key: clock, every: 5, isActive: true),
        ])
        XCTAssertEqual(runtime.due(now: start), [clock, claude])
    }
}
