import Foundation

/// When to read `widgets list` again while a stale catalog holds third-party
/// widgets back: soon at first, then every five minutes, never in a tight loop.
public enum CatalogRetrySchedule {
    public static let firstDelays: [TimeInterval] = [30, 60, 120]
    public static let steadyDelay: TimeInterval = 300

    public static func delay(afterFailures failures: Int) -> TimeInterval? {
        guard failures > 0 else { return nil }
        return failures <= firstDelays.count ? firstDelays[failures - 1] : steadyDelay
    }

    public static func nextAttempt(afterFailures failures: Int, failedAt: Date) -> Date? {
        delay(afterFailures: failures).map { failedAt.addingTimeInterval($0) }
    }
}
