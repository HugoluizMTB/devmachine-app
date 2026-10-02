import Foundation

/// What the Add machine wizard is adding: a server somebody already has, or
/// a Lima machine on this Mac (`devmachine machines create-local`).
public enum MachineKind: String, CaseIterable, Equatable, Sendable {
    case server
    case localVM
}

/// How the server lets somebody in today. A key that already logs in lets
/// `machines add` run with no question; a password goes to its stdin on CLI
/// 0.7.27+, and to the CLI's own question in a terminal on an older one.
public enum ServerLogin: String, CaseIterable, Equatable, Sendable {
    case key
    case password
}

/// Where the key a server already takes comes from: a private key file,
/// or one the SSH agent holds (`--key agent:<fingerprint>`, CLI 0.7.27+).
public enum ServerKeySource: String, CaseIterable, Equatable, Sendable {
    case file
    case agent
}

public enum MachineDraftField: Equatable, Sendable {
    case name, address, user, port, keyFile, agentKey, password, fingerprint, domain, workspace
}

public struct MachineDraftProblem: Equatable, Sendable {
    public let field: MachineDraftField
    public let message: String

    public init(field: MachineDraftField, message: String) {
        self.field = field
        self.message = message
    }
}

/// Every answer the wizard collects, as typed. Defaults are the CLI's own,
/// so an answer left alone adds no flag.
public struct MachineDraft: Equatable, Sendable {
    public static let defaultUser = "root"
    public static let defaultPort = "22"

    public var kind: MachineKind = .server
    public var name = ""
    public var address = ""
    public var user = MachineDraft.defaultUser
    public var port = MachineDraft.defaultPort
    public var login: ServerLogin = .key
    /// The private key the server already takes. Empty only where the CLI
    /// asks its own questions, and then makes a key of its own.
    public var keyFile = ""
    public var keySource: ServerKeySource = .file
    /// The `SHA256:…` fingerprint of the agent key chosen.
    public var agentKey = ""
    /// Handed to `machines add --password-stdin` and nowhere else; it never
    /// reaches a command line, a step's id or a printed draft.
    public var password = SecretText()
    /// The base domain, only for the first machine of all: `machines add
    /// --domain` writes it into the new `config.yml`. Empty adds no flag.
    public var domain = ""
    /// What `machines scan` reported, for the address and port it read.
    public var scan: MachineScan?
    /// The person said the scanned key is the one the console printed.
    public var scanConfirmed = false
    /// What the provider's console printed; the fingerprint is read out of it.
    public var fingerprint = ""
    /// A first workspace to create on the machine; empty creates none.
    public var workspace = ""
    public var essentials = true
    /// Machine packages beyond essentials, in the order they were chosen.
    public var packages: [String] = []
    public var sync = true
    /// The harnesses `skills add --agent` links the skills for (first run).
    public var skillAgents: [String] = []
    /// False before the CLI's `config.yml` exists: only `setup` writes the
    /// first machine, and it asks its questions itself.
    public var hasConfiguration = true

    public init() {}

    public var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedUser: String { user.trimmingCharacters(in: .whitespaces) }
    var trimmedPort: String { port.trimmingCharacters(in: .whitespaces) }
    var trimmedKeyFile: String { keyFile.trimmingCharacters(in: .whitespaces) }
    var trimmedWorkspace: String { workspace.trimmingCharacters(in: .whitespaces) }
    public var trimmedAddress: String { address.trimmingCharacters(in: .whitespaces) }
    public var trimmedDomain: String { domain.trimmingCharacters(in: .whitespaces) }

    /// The `SHA256:…` word in what was pasted: `ssh-keygen -lf` prints it
    /// between the key size and the comment.
    public var expectedFingerprint: String? {
        fingerprint
            .split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "'" })
            .map(String.init)
            .first { $0.range(of: Self.fingerprintPattern, options: .regularExpression) != nil }
    }

    /// The scan, only while it is still about the address and port typed:
    /// a scan of another server says nothing about this one.
    public var currentScan: MachineScan? {
        guard let scan, MachineScan.target(address: trimmedAddress, port: trimmedPort) == scan.target else { return nil }
        return scan
    }

    /// The console output pasted holds the key the server presented.
    public var consoleConfirmsScan: Bool {
        guard let scan = currentScan, let expected = expectedFingerprint else { return false }
        return expected == scan.fingerprint
    }

    /// The console printed a key, the server presented another one.
    public var consoleDisagreesWithScan: Bool {
        guard let scan = currentScan, let expected = expectedFingerprint else { return false }
        return expected != scan.fingerprint
    }

    /// What `machines add --fingerprint` is given: what the console printed,
    /// or the scanned key once the person said it matches the console. A
    /// console and a scan that disagree trust nothing.
    public var fingerprintToTrust: String? {
        if consoleDisagreesWithScan { return nil }
        if let expected = expectedFingerprint { return expected }
        guard let scan = currentScan, scanConfirmed else { return nil }
        return scan.fingerprint
    }

    /// A SHA-256 digest is 32 bytes: 43 base64 characters without padding.
    static let fingerprintPattern = "^SHA256:[A-Za-z0-9+/]{43}=?$"
    static let namePattern = "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
    static let userPattern = "^[a-z_][a-z0-9_-]*$"
    static let domainPattern = "^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"

    /// Mirrors what the CLI would refuse, so the wizard says it before a
    /// command runs: `create-local`'s name rule applies to every machine.
    /// `unattended` is a CLI that takes every answer as a flag
    /// (`MachineUnattendedAdd`): then a password or an agent key is asked
    /// here, and every server needs a fingerprint to trust.
    public func problems(existingMachines: [String], unattended: Bool = false) -> [MachineDraftProblem] {
        var problems: [MachineDraftProblem] = []
        if trimmedName.isEmpty {
            problems.append(.init(field: .name, message: "Give the machine a name."))
        } else if !Self.matches(trimmedName, Self.namePattern) {
            problems.append(.init(field: .name, message: "Use lower-case letters, digits and dashes."))
        } else if existingMachines.contains(trimmedName) {
            problems.append(.init(field: .name, message: "A machine named \(trimmedName) already exists."))
        }
        if kind == .server {
            problems += unattended ? unattendedServerProblems() : serverProblems()
        }
        if !trimmedWorkspace.isEmpty, !Self.matches(trimmedWorkspace, Self.namePattern) {
            problems.append(.init(field: .workspace, message: "Use lower-case letters, digits and dashes."))
        }
        return problems
    }

    private func serverProblems() -> [MachineDraftProblem] {
        var problems = connectionProblems()
        // An unattended `add` stops on a key that does not log in yet, so
        // the key has to be the one the server already takes.
        if login == .key, trimmedKeyFile.isEmpty {
            problems.append(.init(
                field: .keyFile, message: "Type the key file the server already takes, or choose a password login."))
        }
        if login == .key, expectedFingerprint == nil {
            problems.append(.init(
                field: .fingerprint,
                message: "Paste the SHA256 fingerprint your provider's console shows for this server."))
        }
        return problems
    }

    private func connectionProblems() -> [MachineDraftProblem] {
        var problems: [MachineDraftProblem] = []
        if address.isEmpty || address.contains(where: \.isWhitespace) {
            problems.append(.init(field: .address, message: "Type an IP, a hostname, or tailscale:<name>."))
        }
        if !Self.matches(trimmedUser, Self.userPattern) {
            problems.append(.init(field: .user, message: "Type a Linux account, like root."))
        }
        let validPort = Int(trimmedPort).map { (1...65535).contains($0) && String($0) == trimmedPort } ?? false
        if !validPort {
            problems.append(.init(field: .port, message: "Type a port from 1 to 65535."))
        }
        return problems
    }

    private func unattendedServerProblems() -> [MachineDraftProblem] {
        var problems = connectionProblems()
        switch login {
        case .key where keySource == .file && trimmedKeyFile.isEmpty:
            problems.append(.init(
                field: .keyFile, message: "Type the key file the server already takes, or choose a password login."))
        case .key where keySource == .agent && !Self.matches(agentKey, Self.fingerprintPattern):
            problems.append(.init(field: .agentKey, message: "Choose the key the server already takes."))
        case .password where password.value.isEmpty:
            problems.append(.init(field: .password, message: "Type the server's password from your provider."))
        default:
            break
        }
        if consoleDisagreesWithScan {
            problems.append(.init(
                field: .fingerprint,
                message: "The console printed a different key than the server presented. Do not add this server."))
        } else if fingerprintToTrust == nil {
            problems.append(.init(
                field: .fingerprint,
                message: "Read the server's fingerprint and check it against your provider's console."))
        }
        if !hasConfiguration, !trimmedDomain.isEmpty, !Self.matches(trimmedDomain.lowercased(), Self.domainPattern) {
            problems.append(.init(field: .domain, message: "Type a domain like example.com, or leave it empty."))
        }
        return problems
    }

    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
