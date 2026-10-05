import Foundation

/// The updater's own keys, apart from `AppSettings`: turning checks off or
/// skipping a version applies at once, without the Settings page's Save.
public final class UpdatePreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var automaticChecks: Bool {
        get { defaults.object(forKey: "updates.automaticChecks") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "updates.automaticChecks") }
    }

    public var skippedVersion: String? {
        get { defaults.string(forKey: "updates.skippedVersion") }
        set { defaults.set(newValue, forKey: "updates.skippedVersion") }
    }

    public var cliLaterVersion: String? {
        get { defaults.string(forKey: "updates.cliLaterVersion") }
        set { defaults.set(newValue, forKey: "updates.cliLaterVersion") }
    }

    public func cache(for feed: URL) -> CachedRelease? {
        defaults.data(forKey: cacheKey(feed)).flatMap { try? JSONDecoder().decode(CachedRelease.self, from: $0) }
    }

    public func setCache(_ cache: CachedRelease?, for feed: URL) {
        defaults.set(cache.flatMap { try? JSONEncoder().encode($0) }, forKey: cacheKey(feed))
    }

    private func cacheKey(_ feed: URL) -> String {
        "updates.cache.\(feed.absoluteString)"
    }
}
