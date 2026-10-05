import Foundation

/// Where a machine is: a hosting provider, a home, an office, this Mac. The
/// CLI keeps it as `machines[].location` (0.7.30+) and normalises it the way
/// this does; the app groups the network map by it.
public enum MachineLocation {
    public static let minimumCLIVersion = SemanticVersion(major: 0, minor: 7, patch: 30)
    public static let external = "external"
    public static let local = "local"
    static let pattern = "^[a-z0-9][a-z0-9 ._-]{0,39}$"

    public struct Suggestion: Equatable, Sendable, Identifiable {
        public let title: String
        public let value: String
        public var id: String { value }

        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    public static let suggestions = [
        Suggestion(title: "Hostinger", value: "hostinger"),
        Suggestion(title: "Home", value: "home"),
        Suggestion(title: "Office", value: "office"),
        Suggestion(title: "Other cloud", value: "other cloud"),
    ]

    public static func isSupported(cliVersion: SemanticVersion?) -> Bool {
        guard let cliVersion else { return false }
        return cliVersion >= minimumCLIVersion
    }

    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func problem(_ raw: String) -> String? {
        let value = normalized(raw)
        if value.isEmpty { return "Say where it is, like home or hostinger." }
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            return "Use up to 40 letters, digits, spaces, dots, dashes or underscores, starting with a letter or digit."
        }
        return nil
    }

    public static func defaultLocation(for kind: MachineKind) -> String {
        kind == .localVM ? local : external
    }

    /// `reported` is nil when the CLI left the field out (older than
    /// 0.7.30): then this Mac and its Lima machines are local, the rest
    /// external.
    public static func effective(reported: String?, isSelf: Bool, isLocalVM: Bool) -> String {
        guard let reported else { return isSelf || isLocalVM ? local : external }
        let value = normalized(reported)
        return value.isEmpty ? external : value
    }

    /// `create-local` puts a machine on this Mac's loopback, and nothing
    /// else lives there.
    public static func isLocalVM(hosts: [String], isSelf: Bool) -> Bool {
        !isSelf && !hosts.isEmpty && hosts.allSatisfy { $0 == MachinePlan.localAddress }
    }

    /// `--location` for `machines add` and `create-local`, only on a CLI
    /// that takes it.
    public static func flag(_ raw: String, cliVersion: SemanticVersion?) -> [String] {
        let value = normalized(raw)
        guard isSupported(cliVersion: cliVersion), !value.isEmpty else { return [] }
        return ["--location", value]
    }

    public static func editArguments(machine: String, location: String) -> [String] {
        ["machines", "edit", machine, "--location", normalized(location), "--yes"]
    }
}

public enum NetworkAddress {
    /// A tailnet address: a `tailscale:<name>` host, or an IPv4 address in
    /// Tailscale's `100.64.0.0/10`.
    public static func isTailnet(_ host: String) -> Bool {
        if host.hasPrefix("tailscale:") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }), let first = UInt8(parts[0]),
              let second = UInt8(parts[1]) else { return false }
        return first == 100 && (64...127).contains(second)
    }
}
