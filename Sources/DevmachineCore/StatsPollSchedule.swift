import Foundation

public struct StatsPollPolicy: Equatable, Sendable {
    public var interval: TimeInterval
    /// The wait after the 1st, 2nd, 3rd… failure in a row; the last value
    /// repeats.
    public var backoff: [TimeInterval]
    /// The gap between two machines starting together, so a launch or a
    /// manual refresh never opens every ssh connection in the same second.
    public var stagger: TimeInterval

    public init(interval: TimeInterval, backoff: [TimeInterval], stagger: TimeInterval) {
        self.interval = interval
        self.backoff = backoff
        self.stagger = stagger
    }

    public static let standard = StatsPollPolicy(interval: 90, backoff: [90, 180, 300], stagger: 2)

    func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0, !backoff.isEmpty else { return interval }
        return backoff[min(failures, backoff.count) - 1]
    }
}

/// When each machine's stats are next read. Pure bookkeeping with the clock
/// passed in, so the poller's timing is tested without waiting.
public struct StatsPollSchedule: Sendable {
    private struct Entry: Sendable {
        var nextDue: Date
        var failures = 0
        var inFlight = false
    }

    public let policy: StatsPollPolicy
    public private(set) var machines: [String] = []
    private var entries: [String: Entry] = [:]

    public init(policy: StatsPollPolicy = .standard) {
        self.policy = policy
    }

    /// A machine already scheduled keeps its place. A new one is due one
    /// interval after its cached snapshot, or at once (staggered) without one.
    public mutating func setMachines(_ names: [String], lastSuccess: [String: Date], now: Date) {
        var kept: [String: Entry] = [:]
        var newIndex = 0
        for name in names {
            if let existing = entries[name] {
                kept[name] = existing
                continue
            }
            let staggered = now.addingTimeInterval(Double(newIndex) * policy.stagger)
            newIndex += 1
            let fromCache = lastSuccess[name].map { $0.addingTimeInterval(policy.interval) }
            kept[name] = Entry(nextDue: max(staggered, fromCache ?? staggered))
        }
        machines = names
        entries = kept
    }

    public func due(now: Date) -> [String] {
        machines.filter { name in
            guard let entry = entries[name] else { return false }
            return !entry.inFlight && entry.nextDue <= now
        }
    }

    public func nextDue(_ name: String) -> Date? { entries[name]?.nextDue }

    public func isInFlight(_ name: String) -> Bool { entries[name]?.inFlight ?? false }

    /// False when the machine is unknown or already has a run in flight.
    public mutating func begin(_ name: String) -> Bool {
        guard var entry = entries[name], !entry.inFlight else { return false }
        entry.inFlight = true
        entries[name] = entry
        return true
    }

    public mutating func succeed(_ name: String, now: Date) {
        guard var entry = entries[name] else { return }
        entry.inFlight = false
        entry.failures = 0
        entry.nextDue = now.addingTimeInterval(policy.interval)
        entries[name] = entry
    }

    public mutating func fail(_ name: String, now: Date) {
        guard var entry = entries[name] else { return }
        entry.inFlight = false
        entry.failures += 1
        entry.nextDue = now.addingTimeInterval(policy.delay(afterFailures: entry.failures))
        entries[name] = entry
    }

    /// A manual refresh or a wake: every machine is due now, `first` before
    /// the others, and the backoff starts over.
    public mutating func refreshAll(now: Date, first: String? = nil) {
        var order = machines
        if let first, let index = order.firstIndex(of: first) {
            order.remove(at: index)
            order.insert(first, at: 0)
        }
        for (index, name) in order.enumerated() {
            guard var entry = entries[name] else { continue }
            entry.failures = 0
            entry.nextDue = now.addingTimeInterval(Double(index) * policy.stagger)
            entries[name] = entry
        }
    }

    /// Makes one machine due now without touching its backoff.
    public mutating func makeDue(_ name: String, now: Date) {
        guard var entry = entries[name] else { return }
        entry.nextDue = min(entry.nextDue, now)
        entries[name] = entry
    }
}

public enum StatsFreshness {
    /// A few polls missed in a row: the numbers on screen may no longer be
    /// true.
    public static let staleAfter: TimeInterval = 300

    public static func isStale(since collectedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(collectedAt) > staleAfter
    }

    public static func ageText(since collectedAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(collectedAt)))
        switch seconds {
        case ..<60: return "updated just now"
        case ..<3600: return "updated \(seconds / 60)m ago"
        case ..<86_400: return "updated \(seconds / 3600)h ago"
        default: return "updated \(seconds / 86_400)d ago"
        }
    }
}
