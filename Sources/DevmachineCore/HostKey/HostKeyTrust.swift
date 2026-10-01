import Foundation

/// What `devmachine machines trust <machine> --check --format json` read from
/// the server: the key it presented, and the one this Mac trusts for it.
public struct HostKeyReport: Decodable, Equatable, Sendable {
    public enum Status: String, Decodable, Sendable {
        case matching
        case changed
        case missing
    }

    public let machine: String
    public let address: String
    public let status: Status
    public let keyType: String
    /// The pinned key's type, which can differ from the presented one.
    public let currentKeyType: String?
    public let currentFingerprint: String?
    public let presentedFingerprint: String
    /// A command that prints the server's own key of the same type, meant
    /// for the machine's console: an attacker in the middle answers an SSH
    /// session with whatever fingerprint is expected.
    public let verify: String?

    enum CodingKeys: String, CodingKey {
        case machine, address, status, verify
        case keyType = "key_type"
        case currentKeyType = "current_key_type"
        case currentFingerprint = "current_fingerprint"
        case presentedFingerprint = "presented_fingerprint"
    }

    public init(
        machine: String, address: String, status: Status, keyType: String,
        currentKeyType: String? = nil, currentFingerprint: String?, presentedFingerprint: String, verify: String?
    ) {
        self.machine = machine
        self.address = address
        self.status = status
        self.keyType = keyType
        self.currentKeyType = currentKeyType
        self.currentFingerprint = currentFingerprint
        self.presentedFingerprint = presentedFingerprint
        self.verify = verify
    }

    public static func parse(_ json: String) throws -> HostKeyReport {
        try JSONDecoder().decode(HostKeyReport.self, from: Data(json.utf8))
    }
}

/// The CLI calls behind the host key card, and the one check that stands
/// between a changed key and trusting it.
public enum HostKeyTrust {
    /// The first CLI whose `trust --check` reports a changed key as JSON
    /// instead of refusing it.
    public static let minimumCLIVersion = SemanticVersion(major: 0, minor: 7, patch: 24)

    public static func checkArguments(machine: String) -> [String] {
        ["--format", "json", "machines", "trust", machine, "--check"]
    }

    /// Nil when there is nothing to trust. A changed key is replaced only
    /// with `--replace`; `--yes` answers the CLI's own question, which the
    /// app has already asked. `--expect` makes the CLI write only the key the
    /// person verified: it scans again, and a second scan can meet a
    /// different server than the first.
    public static func trustArguments(for report: HostKeyReport) -> [String]? {
        let base = ["--format", "json", "machines", "trust", report.machine]
        let expect = ["--expect", report.presentedFingerprint]
        switch report.status {
        case .matching: return nil
        case .changed: return base + ["--replace", "--yes"] + expect
        case .missing: return base + ["--yes"] + expect
        }
    }

    /// True only when the pasted text holds the presented fingerprint as a
    /// whole word, exactly: what the server's console printed for its own
    /// key. A prefix, the old key or a near miss never counts.
    public static func confirms(_ pasted: String, report: HostKeyReport) -> Bool {
        let words = pasted.split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "'" })
        return words.contains { $0 == report.presentedFingerprint }
    }

    /// ssh's own words when it refuses the key a server presented, changed
    /// or not yet trusted, before any login is tried.
    public static func isHostKeyRejection(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("host key verification failed")
            || lowered.contains("remote host identification has changed")
    }

    /// A CLI older than `minimumCLIVersion` answers `trust --check` on a
    /// changed key with this error instead of a report.
    public static func isOlderCLIRefusal(_ stderr: String) -> Bool {
        stderr.lowercased().contains("host key changed for machine")
    }
}
