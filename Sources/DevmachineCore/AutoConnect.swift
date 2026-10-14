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

// Many logins at once are what a machine's ban counts, so one connects at a time.
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
