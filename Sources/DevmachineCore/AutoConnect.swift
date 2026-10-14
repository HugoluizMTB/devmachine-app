import Foundation

public struct AutoConnectTarget: Hashable, Sendable {
    public let alias: String
    public let session: String

    public init(alias: String, session: String) {
        self.alias = alias
        self.session = session
    }
}

public struct AutoConnectQueue: Sendable {
    public var autoConnect: [String]
    public var hidden: [String]
    public var blocked: Set<String>
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

public enum AutoConnect {
    public static let maxConcurrent = 3
    public static let timeout: TimeInterval = 15
}

// Many logins at once are what a machine's ban counts, so only a few connect at a time.
@MainActor
public final class AutoConnectWarmer<Target: Hashable> {
    public typealias Start = (_ target: Target, _ done: @escaping (_ running: Bool) -> Void) -> Void

    public private(set) var queued: [Target] = []
    public private(set) var inFlight: [Target] = []

    private let timeout: TimeInterval
    private let maxConcurrent: Int
    private let start: Start
    private let isWanted: (Target) -> Bool
    private let hasRoom: () -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let onTimeout: (Target) -> Void
    private var attempts: [Target: Int] = [:]
    private var attempt = 0

    public init(
        timeout: TimeInterval = AutoConnect.timeout,
        maxConcurrent: Int = AutoConnect.maxConcurrent,
        start: @escaping Start,
        isWanted: @escaping (Target) -> Bool,
        hasRoom: @escaping () -> Bool,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        onTimeout: @escaping (Target) -> Void = { _ in }
    ) {
        self.timeout = timeout
        self.maxConcurrent = max(1, maxConcurrent)
        self.start = start
        self.isWanted = isWanted
        self.hasRoom = hasRoom
        self.schedule = schedule
        self.onTimeout = onTimeout
    }

    public func enqueue(_ targets: [Target]) {
        for target in targets where !inFlight.contains(target) && !queued.contains(target) {
            queued.append(target)
        }
        advance()
    }

    private func advance() {
        while inFlight.count < maxConcurrent, !queued.isEmpty {
            let next = queued.removeFirst()
            guard isWanted(next) else { continue }
            guard hasRoom() else {
                queued.removeAll()
                return
            }
            attempt += 1
            let current = attempt
            attempts[next] = current
            inFlight.append(next)
            schedule(timeout) { [weak self] in self?.timedOut(next, current) }
            start(next) { [weak self] _ in self?.finish(next, current) }
        }
    }

    private func timedOut(_ target: Target, _ current: Int) {
        guard attempts[target] == current else { return }
        onTimeout(target)
        finish(target, current)
    }

    private func finish(_ target: Target, _ current: Int) {
        guard attempts[target] == current else { return }
        attempts[target] = nil
        inFlight.removeAll { $0 == target }
        advance()
    }
}
