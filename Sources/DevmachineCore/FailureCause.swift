import Foundation

/// A best guess at why a read failed, from the error text alone, so an
/// error state can say something plain before the person opens the details.
public enum FailureCause: String, CaseIterable, Sendable {
    case signInNeeded
    case permissionDenied
    case timedOut
    case unreachable
    case missingCommand

    public init?(message: String) {
        let lowered = message.lowercased()
        func mentions(_ needles: [String]) -> Bool { needles.contains { lowered.contains($0) } }
        if mentions(["auth login", "not logged in", "not signed in", "unauthorized", "bad credentials"]) {
            self = .signInNeeded
        } else if mentions(["permission denied"]) {
            self = .permissionDenied
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

    public var summary: String {
        switch self {
        case .signInNeeded: "You may need to sign in again."
        case .permissionDenied: "The machine refused the SSH login."
        case .timedOut: "The machine took too long to answer."
        case .unreachable: "The machine can't be reached right now."
        case .missingCommand: "A command it needs isn't installed."
        }
    }
}
