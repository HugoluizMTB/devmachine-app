import Foundation

/// One machine's last good stats, as kept on disk between launches.
/// `collectedAt` is this Mac's clock when the snapshot arrived, so its age
/// never depends on the host's clock.
public struct CachedMachineStats: Codable, Equatable, Sendable {
    public let machine: String
    public let firstAddress: String?
    public let collectedAt: Date
    public let snapshot: StatsSnapshot

    public init(machine: String, firstAddress: String?, collectedAt: Date, snapshot: StatsSnapshot) {
        self.machine = machine
        self.firstAddress = firstAddress
        self.collectedAt = collectedAt
        self.snapshot = snapshot
    }
}

/// The last good snapshot per machine, in one JSON file, so Home and Stats
/// draw at launch before any machine answers. A file that cannot be read
/// is treated as no cache: it only ever costs one poll to rebuild.
public struct StatsCache: Sendable {
    private struct File: Codable {
        let version: Int
        let machines: [CachedMachineStats]
    }

    private static let version = 1

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/stats-cache.json")
    }

    public func load() -> [CachedMachineStats] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.version == Self.version else {
            return []
        }
        return file.machines
    }

    public func save(_ machines: [CachedMachineStats]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(version: Self.version, machines: machines))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
