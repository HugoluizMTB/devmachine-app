import Foundation

/// What the Add machine wizard is adding: a server somebody already has, or
/// a Lima machine on this Mac (`devmachine machines create-local`).
public enum MachineKind: String, CaseIterable, Equatable, Sendable {
    case server
    case localVM
}

/// How the server lets somebody in today. A key that already logs in lets
/// `machines add` run with no question; a password only the CLI may ask
/// for, in a terminal, since an unattended `add` has no way to receive one.
public enum ServerLogin: String, CaseIterable, Equatable, Sendable {
    case key
    case password
}

public enum MachineDraftField: Equatable, Sendable {
    case name, address, user, port, keyFile, fingerprint, workspace
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
    /// What the provider's console printed; the fingerprint is read out of it.
    public var fingerprint = ""
    /// A first workspace to create on the machine; empty creates none.
    public var workspace = ""
    public var essentials = true
    /// Machine packages beyond essentials, in the order they were chosen.
    public var packages: [String] = []
    public var sync = true
    /// False before the CLI's `config.yml` exists: only `setup` writes the
    /// first machine, and it asks its questions itself.
    public var hasConfiguration = true

    public init() {}

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedUser: String { user.trimmingCharacters(in: .whitespaces) }
    var trimmedPort: String { port.trimmingCharacters(in: .whitespaces) }
    var trimmedKeyFile: String { keyFile.trimmingCharacters(in: .whitespaces) }
    var trimmedWorkspace: String { workspace.trimmingCharacters(in: .whitespaces) }

    /// The `SHA256:…` word in what was pasted: `ssh-keygen -lf` prints it
    /// between the key size and the comment.
    public var expectedFingerprint: String? {
        fingerprint
            .split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "'" })
            .map(String.init)
            .first { $0.range(of: Self.fingerprintPattern, options: .regularExpression) != nil }
    }

    /// A SHA-256 digest is 32 bytes: 43 base64 characters without padding.
    static let fingerprintPattern = "^SHA256:[A-Za-z0-9+/]{43}=?$"
    static let namePattern = "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
    static let userPattern = "^[a-z_][a-z0-9_-]*$"

    /// Mirrors what the CLI would refuse, so the wizard says it before a
    /// command runs: `create-local`'s name rule applies to every machine.
    public func problems(existingMachines: [String]) -> [MachineDraftProblem] {
        var problems: [MachineDraftProblem] = []
        if trimmedName.isEmpty {
            problems.append(.init(field: .name, message: "Give the machine a name."))
        } else if !Self.matches(trimmedName, Self.namePattern) {
            problems.append(.init(field: .name, message: "Use lower-case letters, digits and dashes."))
        } else if existingMachines.contains(trimmedName) {
            problems.append(.init(field: .name, message: "A machine named \(trimmedName) already exists."))
        }
        if kind == .server {
            problems += serverProblems()
        }
        if !trimmedWorkspace.isEmpty, !Self.matches(trimmedWorkspace, Self.namePattern) {
            problems.append(.init(field: .workspace, message: "Use lower-case letters, digits and dashes."))
        }
        return problems
    }

    private func serverProblems() -> [MachineDraftProblem] {
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

    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
