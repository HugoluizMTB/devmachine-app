import Foundation

/// The operating systems a package's `platforms` name.
public enum MachinePlatform: String, Equatable, Sendable {
    case linux
    case macos

    public var title: String {
        switch self {
        case .linux: return "Linux"
        case .macos: return "macOS"
        }
    }
}

/// What `setup`, `sync` or `doctor` last read from a machine, as
/// `devmachine --format json machines show <name>` reports it under
/// `observed` (CLI 0.8.0+). A machine nothing read yet has none.
public struct MachineObserved: Equatable, Sendable, Decodable {
    public var system: String
    public var osFamily: String
    public var distribution: String
    public var distributionVersion: String
    public var pkgMgr: String
    public var serviceMgr: String
    public var architecture: String
    public var ansiblePlaybook: String
    /// What a plain SSH command needs in front of `PATH` to find what the
    /// package manager installed (tmux, mosh-server). Empty on Linux.
    public var pathPrefix: [String]

    public static let minimumCLIVersion = SemanticVersion(major: 0, minor: 8, patch: 0)

    public init(
        system: String, osFamily: String = "", distribution: String = "", distributionVersion: String = "",
        pkgMgr: String = "", serviceMgr: String = "", architecture: String = "", ansiblePlaybook: String = "",
        pathPrefix: [String] = []
    ) {
        self.system = system
        self.osFamily = osFamily
        self.distribution = distribution
        self.distributionVersion = distributionVersion
        self.pkgMgr = pkgMgr
        self.serviceMgr = serviceMgr
        self.architecture = architecture
        self.ansiblePlaybook = ansiblePlaybook
        self.pathPrefix = pathPrefix
    }

    enum CodingKeys: String, CodingKey {
        case system, distribution, architecture
        case osFamily = "os_family"
        case distributionVersion = "distribution_version"
        case pkgMgr = "pkg_mgr"
        case serviceMgr = "service_mgr"
        case ansiblePlaybook = "ansible_playbook"
        case pathPrefix = "path_prefix"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: key) ?? "" }
        system = try text(.system)
        osFamily = try text(.osFamily)
        distribution = try text(.distribution)
        distributionVersion = try text(.distributionVersion)
        pkgMgr = try text(.pkgMgr)
        serviceMgr = try text(.serviceMgr)
        architecture = try text(.architecture)
        ansiblePlaybook = try text(.ansiblePlaybook)
        pathPrefix = try c.decodeIfPresent([String].self, forKey: .pathPrefix) ?? []
    }

    private struct ShowEntry: Decodable {
        let observed: MachineObserved?
    }

    public static func isSupported(cliVersion: SemanticVersion?) -> Bool {
        guard let cliVersion else { return false }
        return cliVersion >= minimumCLIVersion
    }

    public static func arguments(machine: String) -> [String] {
        ["--format", "json", "machines", "show", machine]
    }

    /// The `observed` part of one `machines show` entry; nil when the
    /// machine was never read or the answer is not JSON.
    public static func parse(_ json: String) -> MachineObserved? {
        (try? JSONDecoder().decode(ShowEntry.self, from: Data(json.utf8)))?.observed
    }

    public var platform: MachinePlatform? {
        switch system {
        case "Linux": return .linux
        case "Darwin": return .macos
        default: return nil
        }
    }

    /// "macOS 15.7", "Arch Linux", "Ubuntu 24.04".
    public var displayName: String {
        if system == "Darwin" {
            let version = distributionVersion.split(separator: ".").prefix(2).joined(separator: ".")
            return version.isEmpty ? "macOS" : "macOS \(version)"
        }
        let name: String
        switch distribution {
        case "": return system.isEmpty ? "Unknown system" : system
        case "Archlinux": name = "Arch Linux"
        default: name = distribution.prefix(1).uppercased() + distribution.dropFirst()
        }
        return distributionVersion.isEmpty ? name : "\(name) \(distributionVersion)"
    }
}

/// Where accounts live on a machine: `/Users` on a Mac, `/home` on Linux and
/// on a machine never read, which before macOS support was every server.
public enum MachineHome {
    public static func root(system: String?) -> String {
        system == "Darwin" ? "/Users" : "/home"
    }

    public static func folder(user: String, system: String?) -> String {
        root(system: system) + "/" + user
    }
}

/// The system each machine runs, as the packages' `platforms` name it.
/// Unknown (nil) blocks nothing: the CLI's own sync refuses a package for
/// another system once it has read the machine.
public struct MachinePlatforms: Equatable, Sendable {
    public struct Machine: Equatable, Sendable {
        public let name: String
        public let isSelf: Bool

        public init(name: String, isSelf: Bool) {
            self.name = name
            self.isSelf = isSelf
        }
    }

    public var known: [String: MachinePlatform]

    public init(known: [String: MachinePlatform]) {
        self.known = known
    }

    /// Before a CLI could read a machine's system, a server was always
    /// Linux and the self machine is this Mac.
    public static let legacy = MachinePlatforms(known: [:], assumesLinux: true)

    private var assumesLinux = false

    private init(known: [String: MachinePlatform], assumesLinux: Bool) {
        self.known = known
        self.assumesLinux = assumesLinux
    }

    public static func resolve(
        machines: [Machine], observed: [String: MachineObserved], cliVersion: SemanticVersion?
    ) -> MachinePlatforms {
        let assumesLinux = !MachineObserved.isSupported(cliVersion: cliVersion)
        var known: [String: MachinePlatform] = [:]
        for machine in machines {
            if machine.isSelf {
                known[machine.name] = .macos
            } else if let platform = observed[machine.name]?.platform {
                known[machine.name] = platform
            } else if assumesLinux {
                known[machine.name] = .linux
            }
        }
        return MachinePlatforms(known: known, assumesLinux: assumesLinux)
    }

    public func platform(of target: PackageTarget) -> MachinePlatform? {
        if case .machine(_, isSelf: true) = target { return .macos }
        return known[target.syncMachine] ?? (assumesLinux ? .linux : nil)
    }

    public func platform(ofMachine name: String) -> MachinePlatform? {
        known[name] ?? (assumesLinux ? .linux : nil)
    }
}
