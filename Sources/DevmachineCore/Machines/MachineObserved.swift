import Foundation

/// What `setup`, `sync` or `doctor` last read from a machine, as
/// `devmachine --format json machines show <name>` reports it under
/// `observed`. A machine nothing read yet has none.
public struct MachineObserved: Equatable, Sendable, Decodable {
    public var system: String
    public var distribution: String
    public var distributionVersion: String
    public var architecture: String

    public init(system: String, distribution: String = "", distributionVersion: String = "", architecture: String = "") {
        self.system = system
        self.distribution = distribution
        self.distributionVersion = distributionVersion
        self.architecture = architecture
    }

    enum CodingKeys: String, CodingKey {
        case system, distribution, architecture
        case distributionVersion = "distribution_version"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: key) ?? "" }
        system = try text(.system)
        distribution = try text(.distribution)
        distributionVersion = try text(.distributionVersion)
        architecture = try text(.architecture)
    }

    private struct ShowEntry: Decodable {
        let observed: MachineObserved?
    }

    public static func arguments(machine: String) -> [String] {
        ["--format", "json", "machines", "show", machine]
    }

    /// The `observed` part of one `machines show` entry; nil when the
    /// machine was never read or the answer is not JSON.
    public static func parse(_ json: String) -> MachineObserved? {
        (try? JSONDecoder().decode(ShowEntry.self, from: Data(json.utf8)))?.observed
    }

    /// "macOS 15.7", "Arch Linux", "Ubuntu 24.04"; nil when no system was read.
    public var displayName: String? {
        if system == "Darwin" {
            let version = distributionVersion.split(separator: ".").prefix(2).joined(separator: ".")
            return version.isEmpty ? "macOS" : "macOS \(version)"
        }
        guard !system.isEmpty else { return nil }
        let name: String
        switch distribution {
        case "": return system
        case "Archlinux": name = "Arch Linux"
        default: name = distribution.prefix(1).uppercased() + distribution.dropFirst()
        }
        return distributionVersion.isEmpty ? name : "\(name) \(distributionVersion)"
    }

    /// "Ubuntu 24.04 · x86_64".
    public var systemLine: String? {
        guard let displayName else { return nil }
        return architecture.isEmpty ? displayName : "\(displayName) · \(architecture)"
    }

    /// This Mac runs macOS even before anything read it; any other machine
    /// nothing read has no line.
    public static func systemLine(_ observed: MachineObserved?, isSelf: Bool) -> String? {
        observed?.systemLine ?? (isSelf ? "macOS" : nil)
    }
}
