import Foundation

public enum UpdateAvailability: Equatable, Sendable {
    case upToDate
    case available(GitHubRelease)
    case skipped(GitHubRelease)
}

public enum UpdatePolicy {
    public static func evaluate(
        current: SemanticVersion, release: GitHubRelease, skippedVersion: String?
    ) -> UpdateAvailability {
        guard !release.isDraft, !release.isPrerelease,
              let version = release.version, !version.isPrerelease, current < version
        else { return .upToDate }
        if let skippedVersion, SemanticVersion(skippedVersion) == version {
            return .skipped(release)
        }
        return .available(release)
    }
}

/// When to look: 30 seconds after launch, so a check never competes with
/// the app starting up, then every 6 hours.
public struct UpdateSchedule: Sendable {
    public let launchDelay: TimeInterval
    public let interval: TimeInterval

    public init(launchDelay: TimeInterval = 30, interval: TimeInterval = 6 * 3600) {
        self.launchDelay = launchDelay
        self.interval = interval
    }

    public func nextCheck(launchedAt: Date, lastCheckedAt: Date?) -> Date {
        guard let lastCheckedAt else { return launchedAt.addingTimeInterval(launchDelay) }
        return lastCheckedAt.addingTimeInterval(interval)
    }

    public func isDue(now: Date, launchedAt: Date, lastCheckedAt: Date?) -> Bool {
        now >= nextCheck(launchedAt: launchedAt, lastCheckedAt: lastCheckedAt)
    }

    public func delay(now: Date, launchedAt: Date, lastCheckedAt: Date?) -> TimeInterval {
        max(0, nextCheck(launchedAt: launchedAt, lastCheckedAt: lastCheckedAt).timeIntervalSince(now))
    }
}
