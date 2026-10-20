import Foundation

/// Why `machines scan` could not read a server's key, in plain words. The
/// CLI's own error stays in `details` for whoever wants it.
public struct MachineScanFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case refused
        case noAnswer
        case unknownName
        case other
    }

    public let kind: Kind
    public let details: String
    private let port: String

    public init(error: String, port: String = MachineDraft.defaultPort) {
        details = error
        self.port = port.trimmingCharacters(in: .whitespaces)
        kind = Self.kind(of: error.lowercased())
    }

    public var message: String {
        switch kind {
        case .refused:
            return "Nothing answered on port \(port) at this address. Check the address, that the server is on, "
                + "and that the provider firewall allows SSH. If you tried several times, the server may be "
                + "blocking this Mac for a few minutes."
        case .noAnswer: return "The address did not answer."
        case .unknownName: return "That name does not resolve."
        case .other: return "The server's key could not be read."
        }
    }

    private static func kind(of error: String) -> Kind {
        func mentions(_ needles: [String]) -> Bool { needles.contains { error.contains($0) } }
        if error.contains("connection refused") { return .refused }
        if mentions(["no such host", "could not resolve", "nodename nor servname", "server misbehaving",
                     "name resolution"]) {
            return .unknownName
        }
        if mentions(["i/o timeout", "timed out", "no route to host", "network is unreachable", "host is down",
                     "deadline exceeded"]) {
            return .noAnswer
        }
        return .other
    }
}

/// When the wizard reads a server's key by itself: once the address and
/// port could name a server, after typing pauses, and again only when they
/// change.
public enum MachineScanSchedule {
    public static let pause: UInt64 = 700_000_000

    public static func target(address: String, port: String) -> String? {
        let address = address.trimmingCharacters(in: .whitespaces)
        let port = port.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, !address.contains(where: \.isWhitespace),
              let number = Int(port), (1...65535).contains(number), String(number) == port else { return nil }
        return MachineScan.target(address: address, port: port)
    }

    public static func shouldScan(target: String?, scanned: String?, failed: String?) -> Bool {
        guard let target else { return false }
        return target != scanned && target != failed
    }
}

extension MachineScan {
    /// The key type as people name it: `ssh-ed25519` is ED25519.
    public var keyTypeName: String {
        let type = keyType.lowercased()
        if type.contains("ed25519") { return "ED25519" }
        if type.hasPrefix("ecdsa") { return "ECDSA" }
        if type.contains("rsa") { return "RSA" }
        return keyType.uppercased()
    }
}

/// The answer a failed add needs again, asked right on the failure: the
/// password, when the key is not on the server yet or the login was a
/// password (never kept after a run).
public enum MachineRetryField {
    public static let keyNeedsPassword = "the key does not log in yet and no password was given"

    public static func field(failedStep: MachinePlanStep?, lines: [String]) -> MachineDraftField? {
        guard let step = failedStep, step.kind == .addMachine else { return nil }
        if step.input == .password || lines.contains(where: { $0.lowercased().contains(keyNeedsPassword) }) {
            return .password
        }
        return nil
    }
}

/// The private keys in `~/.ssh`: a file whose public half sits beside it.
public enum SSHKeyFiles {
    public static func privateKeys(names: [String]) -> [String] {
        let all = Set(names)
        return names
            .filter { !$0.hasSuffix(".pub") && !$0.hasPrefix(".") && all.contains($0 + ".pub") }
            .sorted()
            .map { "~/.ssh/" + $0 }
    }
}
