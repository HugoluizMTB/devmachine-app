import Foundation

/// `devmachine resolve --format json`: the addresses a machine's `hosts`
/// turn into from here, and why any entry gave none.
public struct MachineAddresses: Equatable, Sendable, Decodable {
    public struct Address: Equatable, Sendable, Decodable {
        public let address: String
        public let source: String
        public let package: String

        public var isTailnet: Bool {
            NetworkAddress.isTailnet(address) || NetworkAddress.isTailnet(source)
        }

        enum CodingKeys: String, CodingKey { case address, source, package }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            address = try c.decode(String.self, forKey: .address)
            source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
            package = try c.decodeIfPresent(String.self, forKey: .package) ?? ""
        }
    }

    public struct Dropped: Equatable, Sendable, Decodable {
        public let source: String
        public let reason: String

        public init(source: String, reason: String) {
            self.source = source
            self.reason = reason
        }
    }

    public let machine: String
    public let addresses: [Address]
    public let dropped: [Dropped]

    enum CodingKeys: String, CodingKey { case machine, addresses, dropped }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machine = try c.decode(String.self, forKey: .machine)
        addresses = try c.decodeIfPresent([Address].self, forKey: .addresses) ?? []
        dropped = try c.decodeIfPresent([Dropped].self, forKey: .dropped) ?? []
    }

    public static func arguments(machine: String) -> [String] {
        ["--format", "json", "resolve", "--machine", machine]
    }

    public static func parse(_ json: String) -> MachineAddresses? {
        try? JSONDecoder().decode(MachineAddresses.self, from: Data(json.utf8))
    }
}

/// `devmachine credentials list --format json`: what the packages on a
/// machine declare, whether the machine has each one, and what delivers it.
/// It logs in to the machine, so it is read only when asked for.
public struct MachineCredentials: Equatable, Sendable, Decodable {
    public struct Credential: Equatable, Sendable, Decodable {
        public let key: String
        public let name: String
        public let kind: String
        public let package: String
        public let workspace: String?
        public let place: String?
        public let status: String
        public let fix: String?
    }

    public let credentials: [Credential]

    public var missing: [Credential] { credentials.filter { $0.status == "missing" } }
    public var unknown: [Credential] { credentials.filter { $0.status == "unknown" } }

    public static func arguments(machine: String) -> [String] {
        ["--format", "json", "credentials", "list", "--machine", machine]
    }

    public static func parse(_ json: String) -> MachineCredentials? {
        try? JSONDecoder().decode(MachineCredentials.self, from: Data(json.utf8))
    }
}

/// `devmachine machines password-login --format json`: what the machine's
/// sshd says, account by account, about logging in with a password. It logs
/// in to the machine, so it is read only when asked for.
public struct MachinePasswordLogin: Equatable, Sendable, Decodable {
    public struct Account: Equatable, Sendable, Decodable {
        public let user: String
        public let allowed: Bool

        enum CodingKeys: String, CodingKey {
            case user
            case allowed = "password_login"
        }
    }

    public let machine: String
    /// The answer for an account no exception names.
    public let allowedByDefault: Bool
    /// Whether the CLI's own sshd file is there.
    public let dropIn: Bool
    public let accounts: [Account]
    /// The accounts the configuration keeps a password for.
    public let keep: [String]

    enum CodingKeys: String, CodingKey {
        case machine, accounts, keep
        case allowedByDefault = "default"
        case dropIn = "drop_in"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machine = try c.decode(String.self, forKey: .machine)
        allowedByDefault = try c.decodeIfPresent(Bool.self, forKey: .allowedByDefault) ?? false
        dropIn = try c.decodeIfPresent(Bool.self, forKey: .dropIn) ?? false
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        keep = try c.decodeIfPresent([String].self, forKey: .keep) ?? []
    }

    public var summary: String {
        if allowedByDefault {
            return dropIn ? "On" : "On (the system's own setting)"
        }
        let kept = accounts.filter(\.allowed).map(\.user)
        return kept.isEmpty ? "Off for every account" : "Off, except for \(kept.joined(separator: ", "))"
    }

    public static func arguments(machine: String) -> [String] {
        ["--format", "json", "machines", "password-login", machine]
    }

    public static func parse(_ json: String) -> MachinePasswordLogin? {
        try? JSONDecoder().decode(MachinePasswordLogin.self, from: Data(json.utf8))
    }
}

/// A change to who logs in over SSH with a password. Keeping nobody is the
/// same as off.
public enum PasswordLoginChange: Equatable, Sendable {
    case off
    case keep([String])
    case on

    public func arguments(machine: String) -> [String] {
        let base = ["machines", "password-login", machine]
        switch self {
        case .off: return base + ["--off", "--yes"]
        case let .keep(accounts) where accounts.isEmpty: return base + ["--off", "--yes"]
        case let .keep(accounts): return base + ["--keep", accounts.joined(separator: ","), "--yes"]
        case .on: return base + ["--on", "--yes"]
        }
    }
}

/// What the CLI does to a Lima machine on this Mac. A bought server is not
/// the CLI's to switch on or off; `delete` destroys the VM, where `machines
/// rm` only forgets a machine.
public enum LocalMachineCommand: Equatable, Sendable {
    case start, stop, delete

    public func arguments(machine: String) -> [String] {
        switch self {
        case .start: return ["machines", "start", machine]
        case .stop: return ["machines", "stop", machine]
        case .delete: return ["machines", "delete-local", machine, "--yes"]
        }
    }

    public func title(machine: String) -> String {
        switch self {
        case .start: return "Start \(machine)"
        case .stop: return "Stop \(machine)"
        case .delete: return "Delete the VM \(machine)"
        }
    }
}
