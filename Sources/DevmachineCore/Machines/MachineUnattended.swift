import Foundation

/// The CLI that takes every answer of `setup` and `machines add` as a flag:
/// `--password-stdin`, `--key agent:…`, `--domain` with no `config.yml`,
/// `machines scan`, `create-local --add`, and an `add` that writes the
/// machine only once its key is proved. An older one still needs a terminal.
public enum MachineUnattendedAdd {
    public static let minimumCLIVersion = SemanticVersion(major: 0, minor: 7, patch: 27)

    public static func isSupported(cliVersion: SemanticVersion?) -> Bool {
        guard let cliVersion else { return false }
        return cliVersion >= minimumCLIVersion
    }
}

/// A value that must never be printed: `description` and a debugger's dump
/// show dots, so a draft logged by mistake carries no password.
public struct SecretText: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public var value: String

    public init(_ value: String = "") {
        self.value = value
    }

    public var description: String { value.isEmpty ? "" : "••••" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// What `devmachine machines scan --format json` reports: the host key a
/// server presents, read without logging in, trusting or writing anything.
public struct MachineScan: Equatable, Sendable, Decodable {
    public let address: String
    public let port: Int
    public let keyType: String
    public let fingerprint: String
    /// A command that prints the same key's fingerprint on the server, for
    /// its own console. Nil for a key type with no standard file.
    public let verify: String?
    /// The address and port as the wizard asked for them, so a scan is never
    /// mistaken for one of another server.
    public private(set) var target = ""

    enum CodingKeys: String, CodingKey {
        case address, port, fingerprint, verify
        case keyType = "key_type"
    }

    public init(address: String, port: Int, keyType: String, fingerprint: String, verify: String?) {
        self.address = address
        self.port = port
        self.keyType = keyType
        self.fingerprint = fingerprint
        self.verify = verify
        target = Self.target(address: address, port: String(port))
    }

    public static func target(address: String, port: String) -> String {
        "\(address.trimmingCharacters(in: .whitespaces)):\(port.trimmingCharacters(in: .whitespaces))"
    }

    public static func arguments(address: String, port: String) -> [String] {
        let port = port.trimmingCharacters(in: .whitespaces)
        return ["--format", "json", "machines", "scan", "--address", address.trimmingCharacters(in: .whitespaces)]
            + (port == MachineDraft.defaultPort ? [] : ["--port", port])
    }

    public static func parse(_ json: String) -> MachineScan? {
        guard var scan = try? JSONDecoder().decode(MachineScan.self, from: Data(json.utf8)),
              MachineDraft.matches(scan.fingerprint, MachineDraft.fingerprintPattern) else { return nil }
        scan.target = target(address: scan.address, port: String(scan.port))
        return scan
    }

    /// The scan as asked for: the CLI reports the address that answered,
    /// which may differ from what was typed (a hostname, say).
    public func asked(address: String, port: String) -> MachineScan {
        var copy = self
        copy.target = Self.target(address: address, port: port)
        return copy
    }
}

/// One key the SSH agent holds, as `ssh-add -l` lists it.
public struct AgentKey: Equatable, Sendable, Identifiable {
    public let fingerprint: String
    public let comment: String
    public let type: String

    public init(fingerprint: String, comment: String, type: String) {
        self.fingerprint = fingerprint
        self.comment = comment
        self.type = type
    }

    public var id: String { fingerprint }

    /// What `machines add --key` takes for it.
    public var keyArgument: String { "agent:\(fingerprint)" }
}

/// The agent's keys, read with `ssh-add -l` against the socket the app hands
/// the CLI, so the list is the one `machines add --key agent:` will search.
public enum AgentKeyList {
    public static let executable = "/usr/bin/ssh-add"
    public static let arguments = ["-l", "-E", "sha256"]

    /// `<bits> SHA256:<digest> <comment> (<TYPE>)` per line; anything else
    /// ("The agent has no identities.") is no key.
    public static func parse(_ output: String) -> [AgentKey] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count >= 2, Int(words[0]) != nil,
                  MachineDraft.matches(words[1], MachineDraft.fingerprintPattern) else { return nil }
            var rest = Array(words.dropFirst(2))
            var type = ""
            if let last = rest.last, last.hasPrefix("("), last.hasSuffix(")") {
                type = String(last.dropFirst().dropLast())
                rest.removeLast()
            }
            return AgentKey(fingerprint: words[1], comment: rest.joined(separator: " "), type: type)
        }
    }
}
