import Foundation

/// One login that leaves an idle tmux copy mode in every session of one
/// account that has a pane on screen.
public struct CopyModeCheck: Equatable, Sendable {
    public let machine: String
    public let alias: String
    public let command: String
}

/// When coming back to the app may check panes for a stray copy mode. tmux
/// runs one server per account, so each workspace alias needs its own
/// login; what is limited is how often: each machine at most once per
/// `interval`, never for a workspace paused after an ssh failure, and never
/// while the sweep is logging in, since stacked logins against a locked
/// agent are what fail2ban bans.
public struct CopyModeCheckSchedule: Sendable {
    public static let defaultInterval: TimeInterval = 5 * 60

    public let interval: TimeInterval
    private var lastChecked: [String: Date] = [:]

    public init(interval: TimeInterval = CopyModeCheckSchedule.defaultInterval) {
        self.interval = interval
    }

    /// The checks due now, by machine then alias, and marks those machines
    /// checked. An alias with no known machine counts as its own; a paused
    /// alias is left out and spends nothing.
    public mutating func due(
        panes: [(alias: String, session: String)], machine: (String) -> String?, now: Date,
        isPaused: (String) -> Bool, sweeping: Bool
    ) -> [CopyModeCheck] {
        guard !sweeping else { return [] }
        var sessions: [String: Set<String>] = [:]
        for pane in panes where !isPaused(pane.alias) { sessions[pane.alias, default: []].insert(pane.session) }
        var checks: [CopyModeCheck] = []
        var checkedMachines: Set<String> = []
        let byMachine = Dictionary(grouping: sessions.keys) { machine($0) ?? $0 }
        for name in byMachine.keys.sorted() {
            if let last = lastChecked[name], now.timeIntervalSince(last) < interval { continue }
            checkedMachines.insert(name)
            for alias in (byMachine[name] ?? []).sorted() {
                let command = (sessions[alias] ?? []).sorted()
                    .map { RemoteCommands.leaveIdleCopyMode(session: $0) }
                    .joined(separator: "; ")
                checks.append(CopyModeCheck(machine: name, alias: alias, command: command))
            }
        }
        for name in checkedMachines { lastChecked[name] = now }
        return checks
    }
}
