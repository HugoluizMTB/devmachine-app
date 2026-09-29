import Foundation

public struct ContainerStat: Decodable, Equatable, Sendable {
    public let name: String
    public let memUsedBytes: Int64
    public let memLimitBytes: Int64
    public let cpuPercent: Double
    /// The context user the container belongs to, when the host says so.
    /// A container started outside a home folder has none, and is shown to
    /// everyone rather than guessed at.
    public let owner: String?

    enum CodingKeys: String, CodingKey {
        case name
        case memUsedBytes = "mem_used_bytes"
        case memLimitBytes = "mem_limit_bytes"
        case cpuPercent = "cpu_percent"
        case owner
    }

    public init(name: String, memUsedBytes: Int64, memLimitBytes: Int64, cpuPercent: Double, owner: String? = nil) {
        self.name = name
        self.memUsedBytes = memUsedBytes
        self.memLimitBytes = memLimitBytes
        self.cpuPercent = cpuPercent
        self.owner = owner
    }
}

public struct UserRAM: Decodable, Equatable, Sendable {
    public let user: String
    public let rssBytes: Int64

    enum CodingKeys: String, CodingKey {
        case user
        case rssBytes = "rss_bytes"
    }

    public init(user: String, rssBytes: Int64) {
        self.user = user
        self.rssBytes = rssBytes
    }
}

public struct PortOwner: Decodable, Equatable, Sendable {
    public let port: Int
    public let owner: String?

    public init(port: Int, owner: String?) {
        self.port = port
        self.owner = owner
    }
}

/// The `devmachine-app` package's `stats` contract
/// (`~/dev/packages/packages/devmachine-app/README.md`): one JSON document
/// per read, replacing a shell snippet the app used to send over ssh and
/// parse itself.
public struct StatsSnapshot: Decodable, Equatable, Sendable {
    public struct Memory: Decodable, Equatable, Sendable {
        public let totalBytes: Int64
        public let usedBytes: Int64
        public let availableBytes: Int64

        enum CodingKeys: String, CodingKey {
            case totalBytes = "total_bytes"
            case usedBytes = "used_bytes"
            case availableBytes = "available_bytes"
        }

        public init(totalBytes: Int64, usedBytes: Int64, availableBytes: Int64) {
            self.totalBytes = totalBytes
            self.usedBytes = usedBytes
            self.availableBytes = availableBytes
        }
    }

    public struct Swap: Decodable, Equatable, Sendable {
        public let totalBytes: Int64
        public let usedBytes: Int64

        enum CodingKeys: String, CodingKey {
            case totalBytes = "total_bytes"
            case usedBytes = "used_bytes"
        }

        public init(totalBytes: Int64, usedBytes: Int64) {
            self.totalBytes = totalBytes
            self.usedBytes = usedBytes
        }
    }

    public struct Disk: Decodable, Equatable, Sendable {
        public let path: String
        public let usedBytes: Int64
        public let availableBytes: Int64
        public let usedPercent: Int

        enum CodingKeys: String, CodingKey {
            case path
            case usedBytes = "used_bytes"
            case availableBytes = "available_bytes"
            case usedPercent = "used_percent"
        }

        public init(path: String, usedBytes: Int64, availableBytes: Int64, usedPercent: Int) {
            self.path = path
            self.usedBytes = usedBytes
            self.availableBytes = availableBytes
            self.usedPercent = usedPercent
        }
    }

    public struct Load: Decodable, Equatable, Sendable {
        public let load1: Double
        public let load5: Double
        public let load15: Double

        public init(load1: Double, load5: Double, load15: Double) {
            self.load1 = load1
            self.load5 = load5
            self.load15 = load15
        }
    }

    public struct Docker: Decodable, Equatable, Sendable {
        public let available: Bool
        public let containers: [ContainerStat]

        public init(available: Bool, containers: [ContainerStat]) {
            self.available = available
            self.containers = containers
        }
    }

    public let collectedAt: String
    public let memory: Memory
    public let swap: Swap
    public let disk: Disk
    public let load: Load
    public let docker: Docker
    public let users: [UserRAM]
    public let ports: [PortOwner]
    public let errors: [String]

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case memory, swap, disk, load, docker, users, ports, errors
    }

    public init(
        collectedAt: String,
        memory: Memory,
        swap: Swap,
        disk: Disk,
        load: Load,
        docker: Docker,
        users: [UserRAM],
        ports: [PortOwner],
        errors: [String]
    ) {
        self.collectedAt = collectedAt
        self.memory = memory
        self.swap = swap
        self.disk = disk
        self.load = load
        self.docker = docker
        self.users = users
        self.ports = ports
        self.errors = errors
    }

    public var containers: [ContainerStat] { docker.containers }
}

public enum StatsParser {
    /// `nil` means the output carries no usable stats — empty text, or
    /// anything that does not decode as the package's JSON contract.
    public static func parse(_ output: String) -> StatsSnapshot? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StatsSnapshot.self, from: data)
    }
}
