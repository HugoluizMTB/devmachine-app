import Foundation

/// One value a sparkline drew, with the time it arrived, so a saved history
/// keeps its spacing across launches.
public struct SparklinePoint: Codable, Equatable, Sendable {
    public let at: Date
    public let value: Double

    public init(at: Date, value: Double) {
        self.at = at
        self.value = value
    }
}

/// A sparkline's last `capacity` points; a widget keeps a bounded past however
/// long the app runs.
public struct SparklineHistory: Codable, Equatable, Sendable {
    public static let capacity = 120

    public private(set) var points: [SparklinePoint] = []

    public init(points: [SparklinePoint] = []) {
        self.points = Array(points.suffix(Self.capacity))
    }

    public mutating func append(_ value: Double, at date: Date) {
        guard value.isFinite else { return }
        points.append(SparklinePoint(at: date, value: value))
        if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
    }
}

/// One small file per widget, so a sparkline draws its past at launch
/// without waiting for 120 polls.
public struct SparklineHistoryStore: Sendable {
    public static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/widget-history")
    }

    public let directory: URL

    public init(directory: URL = SparklineHistoryStore.defaultDirectory) {
        self.directory = directory
    }

    public func fileURL(surface: String, id: String) -> URL {
        directory.appendingPathComponent("\(surface)-\(id).json")
    }

    public func load(surface: String, id: String) -> SparklineHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL(surface: surface, id: id)),
              let history = try? decoder.decode(SparklineHistory.self, from: data)
        else { return SparklineHistory() }
        return SparklineHistory(points: history.points)
    }

    public func save(_ history: SparklineHistory, surface: String, id: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(history).write(to: fileURL(surface: surface, id: id), options: .atomic)
    }
}
