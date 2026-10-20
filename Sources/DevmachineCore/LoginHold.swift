import Foundation

/// A failed call that says the machine turned this Mac's login down. Every
/// refused login counts toward a fail2ban ban of this Mac's IP.
public enum LoginFailure: Equatable, Sendable {
    case refused
    /// Nothing listened on the SSH port. Right after refused logins this is
    /// most likely the server's firewall blocking this Mac.
    case connectionRefused

    public init?(message: String) {
        let lowered = message.lowercased()
        if FailureCause.isSSHLoginRefused(message)
            || ["does not log in", "no more authentication methods", "login-refused"].contains(where: lowered.contains) {
            self = .refused
        } else if lowered.contains("connection refused") {
            self = .connectionRefused
        } else {
            return nil
        }
    }

    /// The `kind` of a workspace's error in `devmachine sessions` JSON.
    public init?(sessionsStatus: String) {
        guard sessionsStatus == "login-refused" else { return nil }
        self = .refused
    }
}

/// Machines the app stopped logging into after the server refused a login.
/// A hold never ends on a timer: only Retry (one attempt), a change to the
/// machine's entry in the CLI's configuration, or a relaunch ends it.
public struct LoginHolds: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case loginRefused
        case probablyBlocked
    }

    public struct Hold: Equatable, Sendable {
        public let reason: Reason
        public let detail: String

        public var title: String {
            switch reason {
            case .loginRefused: "The server refused the login"
            case .probablyBlocked: "The server may be blocking this Mac"
            }
        }

        public var message: String {
            switch reason {
            case .loginRefused:
                "devmachine stopped trying so the server does not block this Mac. "
                    + "Check the machine's key and user, then Retry."
            case .probablyBlocked:
                "The server may be blocking this Mac after failed logins. Wait about 10 minutes, then Retry."
            }
        }
    }

    private var holds: [String: Hold] = [:]
    private var retrying: Set<String> = []
    private var refusedSinceSuccess: Set<String> = []
    private var entries: [String: String]?

    public init() {}

    public func hold(for machine: String) -> Hold? { holds[machine] }

    /// True while automatic calls must not log into the machine, Retry's
    /// own attempt included.
    public func isHeld(_ machine: String) -> Bool { holds[machine] != nil }

    public func isRetrying(_ machine: String) -> Bool { retrying.contains(machine) }

    public var heldMachines: Set<String> { Set(holds.keys) }

    /// Returns true when this failure starts a hold that was not on.
    @discardableResult
    public mutating func record(message: String, machine: String) -> Bool {
        record(LoginFailure(message: message), detail: message, machine: machine)
    }

    @discardableResult
    public mutating func record(_ failure: LoginFailure?, detail: String, machine: String) -> Bool {
        let wasRetrying = retrying.remove(machine) != nil
        let wasHeld = holds[machine] != nil
        switch failure {
        case .refused:
            refusedSinceSuccess.insert(machine)
            holds[machine] = Hold(reason: .loginRefused, detail: detail)
        case .connectionRefused where refusedSinceSuccess.contains(machine):
            holds[machine] = Hold(reason: .probablyBlocked, detail: detail)
        case .connectionRefused, nil:
            if wasRetrying { holds[machine] = nil }
            return false
        }
        return !wasHeld
    }

    /// Only Retry's attempt ends a hold: while one is on nothing automatic
    /// runs, so any other success is a call made before it started, or one
    /// as another user, and proves nothing about the refused login.
    public mutating func recordSuccess(machine: String) {
        if holds[machine] != nil, !retrying.contains(machine) { return }
        holds[machine] = nil
        retrying.remove(machine)
        refusedSinceSuccess.remove(machine)
    }

    /// Lets one attempt through: the caller makes it, and its answer ends
    /// or renews the hold. Automatic calls stay held meanwhile.
    @discardableResult
    public mutating func beginRetry(_ machine: String) -> Bool {
        guard holds[machine] != nil, !retrying.contains(machine) else { return false }
        retrying.insert(machine)
        return true
    }

    /// Retry found nothing to try with: the hold stays as it was.
    public mutating func endRetry(_ machine: String) {
        retrying.remove(machine)
    }

    /// What identifies how the app logs into a machine, so a change to any
    /// part of it reads as a new entry.
    public static func entry(hosts: [String], user: String, port: Int, key: String?, agentKey: String?) -> String {
        [hosts.joined(separator: ","), user, String(port), key ?? "", agentKey ?? ""].joined(separator: "|")
    }

    /// Each machine's login entry (address, user, port, key) as the CLI's
    /// configuration reads now. A changed or removed entry ends that
    /// machine's hold; the first read only remembers them. Returns the
    /// machines released.
    @discardableResult
    public mutating func configurationRead(_ next: [String: String]) -> Set<String> {
        defer { entries = next }
        guard let entries else { return [] }
        let changed = Set(entries.keys).union(next.keys).filter { entries[$0] != next[$0] }
        let released = changed.intersection(holds.keys)
        for machine in changed {
            holds[machine] = nil
            retrying.remove(machine)
            refusedSinceSuccess.remove(machine)
        }
        return released
    }
}
