import Foundation

public struct WidgetRefreshKey: Hashable, Sendable {
    public let provider: String
    public let args: [String: String]

    public init(provider: String, args: [String: String]) {
        self.provider = provider
        self.args = args
    }

    var sortKey: String { provider + "|" + args.keys.sorted().map { "\($0)=\(args[$0] ?? "")" }.joined(separator: ",") }
}

public struct WidgetJob: Equatable, Sendable {
    public let instanceID: String
    public let key: WidgetRefreshKey
    public let every: TimeInterval
    public let isActive: Bool

    public init(instanceID: String, key: WidgetRefreshKey, every: TimeInterval, isActive: Bool) {
        self.instanceID = instanceID
        self.key = key
        self.every = every
        self.isActive = isActive
    }
}

/// Which provider calls are due. Instances that make the same call share
/// one refresh at the shortest interval; a minimized one asks for none.
public struct WidgetRuntime: Sendable {
    private var jobs: [WidgetJob] = []
    private var lastRun: [WidgetRefreshKey: Date] = [:]

    public init() {}

    public var hasActiveJobs: Bool { jobs.contains(where: \.isActive) }

    public mutating func replaceJobs(_ next: [WidgetJob]) {
        jobs = next
        let keys = Set(next.map(\.key))
        lastRun = lastRun.filter { keys.contains($0.key) }
    }

    public func due(now: Date) -> [WidgetRefreshKey] {
        var intervals: [WidgetRefreshKey: TimeInterval] = [:]
        for job in jobs where job.isActive {
            intervals[job.key] = min(intervals[job.key] ?? .infinity, job.every)
        }
        return intervals
            .filter { key, every in lastRun[key].map { now.timeIntervalSince($0) >= every } ?? true }
            .map(\.key)
            .sorted { $0.sortKey < $1.sortKey }
    }

    public mutating func markRan(_ keys: [WidgetRefreshKey], at date: Date) {
        for key in keys { lastRun[key] = date }
    }
}
