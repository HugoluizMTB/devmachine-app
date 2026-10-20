import Foundation

/// How a step that downloads is tried again before it fails: a dropped
/// connection or a slow mirror often works a few seconds later, so the
/// person sees the error only once the network kept failing.
public struct RetryPolicy: Equatable, Sendable {
    public let maxAttempts: Int
    /// The wait after each failed attempt; the last one repeats.
    public let delays: [TimeInterval]

    public init(maxAttempts: Int, delays: [TimeInterval]) {
        self.maxAttempts = maxAttempts
        self.delays = delays
    }

    public static let downloads = RetryPolicy(maxAttempts: 3, delays: [2, 5])

    /// The wait before the next attempt, or nil when the step fails now:
    /// every attempt is spent, or `output` names a cause other than the network.
    public func delay(afterFailedAttempts failed: Int, output: [String]) -> TimeInterval? {
        guard failed >= 1, failed < maxAttempts, !delays.isEmpty, NetworkFailure.isTransient(output) else {
            return nil
        }
        return delays[min(failed - 1, delays.count - 1)]
    }
}

/// Whether a failure's output blames the network. A cause that another try
/// cannot fix (a refused login, a changed host key, a bad checksum, a flag
/// the CLI does not know) wins over any network words in the same output.
public enum NetworkFailure {
    private static let networkWords = [
        "could not resolve", "no such host", "dial tcp", "i/o timeout", "timed out", "timeout",
        "connection reset", "connection refused", "network is unreachable", "no route to host",
        "tls handshake", "temporary failure in name resolution", "offline", "could not connect",
        "network connection was lost", "unexpected eof", "broken pipe", "the server answered 5",
        "the server answered 429",
    ]

    private static let permanentWords = [
        "host key verification failed", "remote host identification has changed", "checksum",
        "unknown flag", "unknown command", "authentication failed",
    ]

    public static func isTransient(_ output: [String]) -> Bool {
        let lines = output.suffix(40).map { $0.lowercased() }
        if lines.contains(where: { line in
            FailureCause.isSSHLoginRefused(line) || permanentWords.contains { line.contains($0) }
        }) {
            return false
        }
        return lines.contains { line in networkWords.contains { line.contains($0) } }
    }
}
