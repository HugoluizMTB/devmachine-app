import Foundation

public struct SourceJob: Equatable, Sendable {
    public let instanceID: String
    public let every: WidgetEvery
    /// Approved (or needing no approval), and not in demo mode.
    public let isRunnable: Bool
    /// On screen and not minimized.
    public let isVisible: Bool
    /// What runs; a new one starts the widget over.
    public let signature: String

    public init(instanceID: String, every: WidgetEvery, isRunnable: Bool, isVisible: Bool, signature: String) {
        self.instanceID = instanceID
        self.every = every
        self.isRunnable = isRunnable
        self.isVisible = isVisible
        self.signature = signature
    }

    /// Never polls faster than the contract's minimum for the source's kind,
    /// whatever reached the resolved source.
    public init(
        instanceID: String, source: ResolvedSource, isRunnable: Bool, isVisible: Bool, signature: String,
        contract: WidgetContract = .current
    ) {
        var every = source.every
        if case let .interval(seconds) = every, let floor = contract.minimumInterval(forSource: source.source.kind) {
            every = .interval(max(floor, seconds))
        }
        self.init(instanceID: instanceID, every: every, isRunnable: isRunnable, isVisible: isVisible, signature: signature)
    }
}

/// Which source widgets run now. Unlike provider jobs, each widget runs on
/// its own: two commands that look alike may run on different targets.
/// A widget whose run came back waiting for approval, or denied, is paused:
/// not in flight, and not run again until approvals change or what it runs does.
public struct SourceSchedule: Sendable {
    private var jobs: [String: SourceJob] = [:]
    private var lastRun: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private var paused: Set<String> = []

    public init() {}

    public mutating func replaceJobs(_ next: [SourceJob]) {
        let map = Dictionary(next.map { ($0.instanceID, $0) }, uniquingKeysWith: { _, last in last })
        for (id, old) in jobs where map[id]?.signature != old.signature {
            lastRun[id] = nil
            paused.remove(id)
        }
        lastRun = lastRun.filter { map[$0.key] != nil }
        paused = paused.filter { map[$0] != nil }
        jobs = map
    }

    public func due(now: Date) -> [String] {
        jobs.values.filter { job in
            guard isEligible(job), job.isVisible, case let .interval(seconds) = job.every else { return false }
            return lastRun[job.instanceID].map { now.timeIntervalSince($0) >= seconds } ?? true
        }
        .map(\.instanceID)
        .sorted()
    }

    public func canRunNow(_ id: String) -> Bool {
        guard let job = jobs[id] else { return false }
        return isEligible(job)
    }

    public mutating func begin(_ id: String, at date: Date) {
        inFlight.insert(id)
        lastRun[id] = date
    }

    public mutating func finish(_ id: String) {
        inFlight.remove(id)
    }

    public func isInFlight(_ id: String) -> Bool { inFlight.contains(id) }

    public mutating func pause(_ id: String, for state: ApprovalState) {
        guard !state.canRun, jobs[id] != nil else { return }
        paused.insert(id)
    }

    public func isPaused(_ id: String) -> Bool { paused.contains(id) }

    public mutating func resumeAll() {
        paused.removeAll()
    }

    public var streams: Set<String> {
        Set(jobs.values.filter { $0.every == .continuous && isEligible($0) && $0.isVisible }.map(\.instanceID))
    }

    private func isEligible(_ job: SourceJob) -> Bool {
        job.isRunnable && !inFlight.contains(job.instanceID) && !paused.contains(job.instanceID)
    }
}

/// What a source widget shows: the last good output stays when a later run
/// fails, next to the error.
public struct SourceWidgetState: Equatable, Sendable {
    public var output: SourceOutput?
    public var error: SourceError?
    public var isRunning = false
    public var lastSuccess: Date?
    public var lines: [String] = []
    public var ended = false

    public init() {}
}
