import XCTest
@testable import DevmachineCore

final class CatalogRetryScheduleTests: XCTestCase {
    func testTheDelaysDoubleThenSettleOnFiveMinutes() {
        XCTAssertEqual((1...7).map { CatalogRetrySchedule.delay(afterFailures: $0) }, [30, 60, 120, 300, 300, 300, 300])
    }

    func testNoFailureMeansNoRetry() {
        XCTAssertNil(CatalogRetrySchedule.delay(afterFailures: 0))
        XCTAssertNil(CatalogRetrySchedule.nextAttempt(afterFailures: 0, failedAt: Date(timeIntervalSince1970: 0)))
    }

    func testTheNextAttemptCountsFromTheFailure() {
        let failedAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(CatalogRetrySchedule.nextAttempt(afterFailures: 1, failedAt: failedAt), Date(timeIntervalSince1970: 1_030))
        XCTAssertEqual(CatalogRetrySchedule.nextAttempt(afterFailures: 3, failedAt: failedAt), Date(timeIntervalSince1970: 1_120))
        XCTAssertEqual(CatalogRetrySchedule.nextAttempt(afterFailures: 9, failedAt: failedAt), Date(timeIntervalSince1970: 1_300))
    }
}
