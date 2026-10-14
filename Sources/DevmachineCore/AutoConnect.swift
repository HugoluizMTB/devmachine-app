import Foundation

/// One session of a workspace to connect in the background.
public struct AutoConnectTarget: Hashable, Sendable {
    public let alias: String
    public let session: String

    public init(alias: String, session: String) {
        self.alias = alias
        self.session = session
    }
}

/// Which sessions "Auto-connect on startup" reaches: those of the chosen
/// workspaces that have no terminal yet, never a hidden workspace or one held
/// back from automatic logins (paused, host key refused, waiting for sync).
public struct AutoConnectQueue: Sendable {
    public var autoConnect: [String]
    public var hidden: [String]
    /// Workspaces, by ssh alias, that no automatic login may reach now.
    public var blocked: Set<String>
    /// Sessions that already have a terminal, connected or connecting.
    public var open: Set<AutoConnectTarget>

    public init(autoConnect: [String], hidden: [String], blocked: Set<String>, open: Set<AutoConnectTarget>) {
        self.autoConnect = autoConnect
        self.hidden = hidden
        self.blocked = blocked
        self.open = open
    }

    public func isWanted(_ target: AutoConnectTarget) -> Bool {
        Self.lists(autoConnect, target.alias)
            && !Self.lists(hidden, target.alias)
            && !blocked.contains(target.alias)
            && !open.contains(target)
    }

    private static func lists(_ aliases: [String], _ alias: String) -> Bool {
        aliases.contains { $0.lowercased() == alias.lowercased() }
    }

    /// The sessions to add behind `queued`, in the order given, so that the
    /// queue never holds more than `room` sessions: the terminals that can
    /// still be kept open without closing one.
    public func targets(
        sessions: [(alias: String, sessions: [String])], queued: [AutoConnectTarget], room: Int
    ) -> [AutoConnectTarget] {
        var result: [AutoConnectTarget] = []
        let limit = room - queued.count
        guard limit > 0 else { return [] }
        let alreadyQueued = Set(queued)
        for (alias, names) in sessions {
            for name in names {
                let target = AutoConnectTarget(alias: alias, session: name)
                guard isWanted(target), !alreadyQueued.contains(target), !result.contains(target) else { continue }
                result.append(target)
                if result.count == limit { return result }
            }
        }
        return result
    }
}

/// Starts queued connections one at a time: the next waits until the one
/// before it is running, failed, or took longer than `timeout`. Many logins
/// at once are what a machine's ban counts.
@MainActor
public final class AutoConnectWarmer<Target: Hashable> {
    public typealias Start = (_ target: Target, _ done: @escaping (_ running: Bool) -> Void) -> Void

    public private(set) var queued: [Target] = []
    public private(set) var inFlight: Target?

    private let timeout: TimeInterval
    private let start: Start
    private let isWanted: (Target) -> Bool
    private let hasRoom: () -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var attempt = 0

    public init(
        timeout: TimeInterval = 15,
        start: @escaping Start,
        isWanted: @escaping (Target) -> Bool,
        hasRoom: @escaping () -> Bool,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void
    ) {
        self.timeout = timeout
        self.start = start
        self.isWanted = isWanted
        self.hasRoom = hasRoom
        self.schedule = schedule
    }

    public func enqueue(_ targets: [Target]) {
        for target in targets where target != inFlight && !queued.contains(target) {
            queued.append(target)
        }
        advance()
    }

    private func advance() {
        guard inFlight == nil else { return }
        while !queued.isEmpty {
            let next = queued.removeFirst()
            guard isWanted(next) else { continue }
            guard hasRoom() else {
                queued.removeAll()
                return
            }
            attempt += 1
            let current = attempt
            inFlight = next
            schedule(timeout) { [weak self] in self?.finish(current) }
            start(next) { [weak self] _ in self?.finish(current) }
            return
        }
    }

    private func finish(_ current: Int) {
        guard current == attempt, inFlight != nil else { return }
        inFlight = nil
        advance()
    }
}
