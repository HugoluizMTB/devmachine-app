import Foundation

/// A best guess at why a read failed, from the error text alone, so an
/// error state can say something plain before the person opens the details.
public enum FailureCause: String, CaseIterable, Sendable {
    case signInNeeded
    case permissionDenied
    case fileAccessDenied
    case timedOut
    case unreachable
    case missingCommand
    case hostKeyRejected
    case cliSocketPathTooLong

    public init?(message: String) {
        let lowered = message.lowercased()
        func mentions(_ needles: [String]) -> Bool { needles.contains { lowered.contains($0) } }
        if mentions(["too long for unix domain socket"]) {
            // ssh refuses the CLI's connection-sharing socket when the path
            // under a long home folder passes the OS's 104-byte limit; a
            // newer CLI keeps that path short.
            self = .cliSocketPathTooLong
        } else if mentions(["auth login", "not logged in", "not signed in", "unauthorized", "bad credentials"]) {
            self = .signInNeeded
        } else if Self.isSSHLoginRefused(message) {
            self = .permissionDenied
        } else if HostKeyTrust.isHostKeyRejection(message) {
            // Any SSH connection: a git push from the server to GitHub too,
            // so it does not say which machine.
            self = .hostKeyRejected
        } else if mentions(["permission denied", "operation not permitted"]) {
            self = .fileAccessDenied
        } else if mentions(["timed out", "timeout"]) {
            self = .timedOut
        } else if mentions(["could not resolve", "connection refused", "no route to host",
                            "network is unreachable", "host is down", "connection closed"]) {
            self = .unreachable
        } else if mentions(["command not found", "no such file or directory", "executable not found"]) {
            self = .missingCommand
        } else {
            return nil
        }
    }

    /// ssh's own words when the machine turns the login down. Any other
    /// "Permission denied" comes from a command that did log in — git or rm
    /// meeting a file this account cannot change — and must not read as a
    /// refused login.
    public static func isSSHLoginRefused(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("permission denied (")
            || lowered.contains("permission denied, please try again")
            || lowered.contains("too many authentication failures")
    }

    public var summary: String {
        switch self {
        case .signInNeeded: "You may need to sign in again."
        case .permissionDenied: "The machine refused the SSH login."
        case .fileAccessDenied: "This account can't change some of the files."
        case .timedOut: "The machine took too long to answer."
        case .unreachable: "The machine can't be reached right now."
        case .missingCommand: "A command it needs isn't installed."
        case .hostKeyRejected: "An SSH host key wasn't trusted, so the connection stopped before logging in."
        case .cliSocketPathTooLong:
            "This devmachine CLI cannot connect from this Mac's home folder; update it with devmachine update."
        }
    }

    /// Only a newer CLI fixes it: the error state offers the update.
    public var needsCLIUpdate: Bool { self == .cliSocketPathTooLong }
}
