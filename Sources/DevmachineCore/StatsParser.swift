import Foundation

public struct ContainerStat: Equatable, Sendable {
    public let name: String
    public let mem: String
    public let cpu: String
    /// The context user the container belongs to, when the host says so.
    /// A container started outside a home folder has none, and is shown to
    /// everyone rather than guessed at.
    public var owner: String?

    public init(name: String, mem: String, cpu: String) {
        self.name = name
        self.mem = mem
        self.cpu = cpu
    }
}

public struct UserRAM: Equatable, Sendable {
    public let user: String
    public let rssBytes: Int64

    public init(user: String, rssBytes: Int64) {
        self.user = user
        self.rssBytes = rssBytes
    }
}

public struct StatsSnapshot: Equatable, Sendable {
    public let memTotal: Int64
    public let memUsed: Int64
    public let memAvailable: Int64
    public let swapTotal: Int64
    public let swapUsed: Int64
    public let diskUsed: Int64
    public let diskAvail: Int64
    public let diskPercent: Int
    public let load1: Double
    public let load5: Double
    public let load15: Double
    public let containers: [ContainerStat]
    public let users: [UserRAM]

    public init(
        memTotal: Int64,
        memUsed: Int64,
        memAvailable: Int64,
        swapTotal: Int64,
        swapUsed: Int64,
        diskUsed: Int64,
        diskAvail: Int64,
        diskPercent: Int,
        load1: Double,
        load5: Double,
        load15: Double,
        containers: [ContainerStat],
        users: [UserRAM]
    ) {
        self.memTotal = memTotal
        self.memUsed = memUsed
        self.memAvailable = memAvailable
        self.swapTotal = swapTotal
        self.swapUsed = swapUsed
        self.diskUsed = diskUsed
        self.diskAvail = diskAvail
        self.diskPercent = diskPercent
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.containers = containers
        self.users = users
    }
}

public enum StatsParser {
    /// `nil` means the output carries no usable stats — a dropped connection,
    /// a failed command, or anything else that returns empty or unrecognized
    /// text. Memory is the one section every host always has, so its absence
    /// (or a total of zero, which a real host never reports) is what tells a
    /// failed read apart from a host that is genuinely idle everywhere else.
    public static func parse(_ output: String) -> StatsSnapshot? {
        let sections = splitSections(output)

        let memValues = ints(sections["@@MEM@@"]?.first)
        guard let memTotal = memValues.first, memTotal > 0 else { return nil }

        let swapValues = ints(sections["@@SWAP@@"]?.first)
        let diskLine = sections["@@DISK@@"]?.first
        let diskValues = ints(diskLine)
        let loadValues = doubles(sections["@@LOAD@@"]?.first)

        return StatsSnapshot(
            memTotal: memTotal,
            memUsed: memValues.count > 1 ? memValues[1] : 0,
            memAvailable: memValues.count > 2 ? memValues[2] : 0,
            swapTotal: swapValues.count > 0 ? swapValues[0] : 0,
            swapUsed: swapValues.count > 1 ? swapValues[1] : 0,
            diskUsed: diskValues.count > 0 ? diskValues[0] : 0,
            diskAvail: diskValues.count > 1 ? diskValues[1] : 0,
            diskPercent: diskPercent(from: diskLine),
            load1: loadValues.count > 0 ? loadValues[0] : 0,
            load5: loadValues.count > 1 ? loadValues[1] : 0,
            load15: loadValues.count > 2 ? loadValues[2] : 0,
            containers: parseContainers(
                sections["@@DOCKER@@"] ?? [],
                owners: Ownership.containerOwners(
                    (sections["@@OWNERS@@"] ?? []).joined(separator: "\n"))),
            users: parseUsers(sections["@@USERS@@"] ?? [])
        )
    }

    private static func splitSections(_ output: String) -> [String: [String]] {
        var sections: [String: [String]] = [:]
        var currentKey: String?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("@@") && line.hasSuffix("@@") {
                currentKey = line
                sections[line] = []
                continue
            }
            guard let key = currentKey else { continue }
            if !line.isEmpty {
                sections[key, default: []].append(line)
            }
        }

        return sections
    }

    private static func ints(_ line: String?) -> [Int64] {
        guard let line else { return [] }
        return line.split(separator: " ").compactMap { Int64($0) }
    }

    private static func doubles(_ line: String?) -> [Double] {
        guard let line else { return [] }
        return line.split(separator: " ").compactMap { Double($0) }
    }

    private static func diskPercent(from line: String?) -> Int {
        guard let line else { return 0 }
        let parts = line.split(separator: " ")
        guard let last = parts.last else { return 0 }
        return Int(last.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) ?? 0
    }

    private static func parseContainers(_ lines: [String], owners: [String: String])
        -> [ContainerStat] {
        lines.compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3 else { return nil }
            var stat = ContainerStat(name: parts[0], mem: parts[1], cpu: parts[2])
            stat.owner = owners[parts[0]]
            return stat
        }
    }

    private static func parseUsers(_ lines: [String]) -> [UserRAM] {
        let users: [UserRAM] = lines.compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let rssKB = Int64(parts[1]) else { return nil }
            return UserRAM(user: String(parts[0]), rssBytes: rssKB * 1024)
        }
        return users.sorted { $0.rssBytes > $1.rssBytes }
    }
}
